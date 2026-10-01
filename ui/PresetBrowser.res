// The preset browser: searches the programs in the bank, the banks bundled with the plugin,
// the banks in the user's bank folders and any files opened in it, by name, category, tags,
// author and description (Library.res). Clicking a preset plays it (unless preview is off)
// without storing it anywhere; Load puts it into the current program, or goes to it if it is
// one of the bank's, and Cancel puts back what was playing. The browser keeps its search and
// filters for as long as the view is open. In the plugin, the bank folders' banks and the opened
// files are kept by the plugin (BankLibrary), so they're there the next time the window opens;
// elsewhere opened files last as long as the view.

open! Web

@set external setSpellcheck: (element, bool) => unit = "spellcheck"
@set external setScrollTop: (element, float) => unit = "scrollTop"
@get external scrollTop: element => float = "scrollTop"

type t = {
  ctx: Ctx.t,
  stage: element,
  settings: Settings.t,
  bank: Library.source,
  bundled: array<Library.source>,
  // the plugin's bank library, and a source for each of its banks (by "lib:" and its id), with
  // the version it holds; files kept while the plugin hasn't listed them yet
  library: BankLibrary.t,
  mutable cached: array<(Library.source, string)>,
  keeping: Set.t<string>,
  mutable reading: bool,
  mutable opened: array<Library.source>,
  mutable text: string,
  mutable filters: Library.filters,
  mutable bundledRead: bool,
  mutable nextFileId: int,
  // while open: re-render, and add dropped files
  mutable refresh: option<unit => unit>,
  mutable addFiles: option<array<file> => unit>,
}

let isOpen = t => t.refresh != None

let sources = t => [t.bank, ...t.bundled, ...t.cached->Array.map(((s, _)) => s), ...t.opened]

let refresh = t => t.refresh->Option.forEach(fn => fn())

let libraryId = (bank: BankLibrary.bank) => "lib:" ++ bank.id

// The library bank a source shows.
let bankOf = (t, source: Library.source) => t.library.banks->Array.find(b => libraryId(b) == source.id)

// Reads the library's banks that aren't read yet, one at a time.
let rec readLibrary = t =>
  if !t.reading {
    t.cached
    ->Array.find(((s, _)) => s.status == Loading)
    ->Option.forEach(((source, _)) =>
      switch bankOf(t, source) {
      | Some(bank) =>
        t.reading = true
        t.library
        ->BankLibrary.presets(bank)
        ->Promise.thenResolve(result => {
          t.reading = false
          switch result {
          | Ok(presets) =>
            source.presets = presets
            source.status = Ready
          | Error(e) => source.status = Failed(e)
          }
          refresh(t)
          readLibrary(t)
        })
        ->Promise.ignore
      | None => ()
      }
    )
  }

// A source for each of the library's banks, kept while its version stays (so a selection in it
// stays too), and the files being kept until the library lists them.
let syncLibrary = t => {
  let listed = t.library.banks->Array.map(bank => {
    let id = libraryId(bank)
    let version = BankLibrary.versionKey(bank)
    t.keeping->Set.delete(bank.id)->ignore
    switch t.cached->Array.find(((s, v)) => s.id == id && v == version) {
    | Some(kept) => kept
    | None =>
      let source = Library.makeSource(~id, ~name=bank.name, ~kind=Cached)
      switch BankLibrary.parsed->Map.get(version) {
      | Some(Ok(presets)) =>
        source.presets = presets
        source.status = Ready
      | Some(Error(e)) => source.status = Failed(e)
      | None => ()
      }
      (source, version)
    }
  })
  let pending = t.cached->Array.filter(((s, _)) =>
    t.keeping->Set.has(s.id->String.slice(~start=4)) && !(listed->Array.some(((l, _)) => l.id == s.id))
  )
  // the folders' banks first, then the opened files
  let isOpened = ((s, _)) => bankOf(t, s)->Option.mapOr(true, b => b.origin == Opened)
  t.cached = [...listed->Array.filter(x => !isOpened(x)), ...listed->Array.filter(isOpened), ...pending]
  readLibrary(t)
  refresh(t)
}

let make = (ctx: Ctx.t, stage, settings) => {
  let t = {
    ctx,
    stage,
    settings,
    bank: Library.makeSource(~id="bank", ~name="This bank", ~kind=Bank),
    bundled: Library.bundled->Array.map(((id, name, _)) => Library.makeSource(~id, ~name, ~kind=Bundled)),
    library: BankLibrary.make(ctx.pc, settings),
    cached: [],
    keeping: Set.make(),
    reading: false,
    opened: [],
    text: "",
    filters: Library.noFilters,
    bundledRead: false,
    nextFileId: 0,
    refresh: None,
    addFiles: None,
  }
  t.library->BankLibrary.listen(() => syncLibrary(t))
  t
}

let dispose = t => t.library->BankLibrary.dispose

let readBundled = t =>
  if !t.bundledRead {
    t.bundledRead = true
    Library.bundled->Array.forEachWithIndex(((_, _, path), i) => {
      let source = t.bundled->Array.getUnsafe(i)
      Resources.readBytes(t.ctx.pc, path)
      ->Promise.thenResolve(bytes => {
        switch bytes->Option.map(Preset.parseFile) {
        | Some(Ok({presets})) =>
          source.presets = presets
          source.status = Ready
        | Some(Error(e)) => source.status = Failed(e)
        | None => source.status = Failed("not found")
        }
        t.refresh->Option.forEach(fn => fn())
      })
      ->Promise.ignore
    })
  }

// The extension a file is kept under in the library: Porridge's own JSON as .porridge.
let keptExtension = name => {
  let ext = name->String.toLowerCase->String.slice(~start=String.length(baseName(name)))
  ext == ".json" || ext == "" ? ".porridge" : ext
}

// Reads files into sources of their own (in the plugin, kept in its library); returns the ones
// that could be read.
let readFiles = async (t, files: array<file>) => {
  let added = []
  for i in 0 to Array.length(files) - 1 {
    let file = files->Array.getUnsafe(i)
    let bytes = await readBytes(file)
    switch (bytes, bytes->Result.flatMap(Preset.parseForLoading(_, file->fileName))) {
    | (Ok(bytes), Ok({presets})) if t.library.available =>
      let name = baseName(file->fileName)
      let id = t.library->BankLibrary.keep(~name, ~ext=keptExtension(file->fileName), bytes, presets)
      let sourceId = "lib:" ++ id
      let source = switch t.cached->Array.find(((s, _)) => s.id == sourceId) {
      | Some((s, _)) => s
      | None =>
        let s = Library.makeSource(~id=sourceId, ~name, ~kind=Cached, ~presets)
        t.keeping->Set.add(id)
        t.cached = [...t.cached, (s, id)]
        s
      }
      added->Array.push(source)
    | (_, Ok({presets})) =>
      t.nextFileId = t.nextFileId + 1
      let source = Library.makeSource(
        ~id="file" ++ Int.toString(t.nextFileId),
        ~name=baseName(file->fileName),
        ~kind=File,
        ~presets,
      )
      t.opened = [...t.opened, source]
      added->Array.push(source)
    | (_, Error(e)) => t.ctx.toast(e)
    }
  }
  added
}

let previewSetting = "browserPreview"

let previewOn = t => t.settings->Settings.bool(previewSetting, ~default=true)

// at most this many rows are built; the rest wait for a narrower search
let maxRows = 400

let show = t => {
  let ctx = t.ctx
  let programs = ctx.programs
  ctx.menu->Menu.close
  readBundled(t)
  t.library->BankLibrary.refresh

  // the current program as it is, live edits included: what Cancel puts back
  let kept = programs->ProgramStore.captureCurrent
  let previewed = ref(false)
  t.bank.presets = programs.programs->Array.mapWithIndex((p, i) => i == programs.current ? kept : p)

  let shade = el("div", ~cls="shade", ~parent=t.stage)
  let root = el("div", ~cls="brw", ~parent=shade)

  // header: title, search, count
  let head = el("div", ~cls="brw-head", ~parent=root)
  el("div", ~cls="brw-title", ~text="Browse", ~parent=head)->ignore
  let searchBox = el("div", ~cls="brw-search", ~parent=head)
  let input = el("input", ~parent=searchBox)
  input->setPlaceholder("search names, tags, categories, authors…   tag:wide  cat:pad  author:porridge")
  input->setSpellcheck(false)
  input->setValue(t.text)
  let clearText = el("button", ~cls="brw-x", ~text="✕", ~parent=searchBox)
  let count = el("div", ~cls="brw-count", ~parent=head)

  let body = el("div", ~cls="brw-body", ~parent=root)
  let side = el("div", ~cls="brw-side", ~parent=body)
  let list = el("div", ~cls="brw-list", ~parent=body)
  let info = el("div", ~cls="brw-info", ~parent=body)

  let foot = el("div", ~cls="brw-foot", ~parent=root)
  let previewToggle = el("div", ~cls="tg brw-prev", ~parent=foot)
  el("b", ~parent=previewToggle)->ignore
  el("span", ~text="play on click", ~parent=previewToggle)->ignore
  let hint = el(
    "div",
    ~cls="brw-hint",
    ~text="↑ ↓ to move · Enter to load · Esc to cancel · drop files here to browse them",
    ~parent=foot,
  )
  hint->ignore
  let cancelButton = el("button", ~cls="btn", ~text="Cancel", ~parent=foot)
  let loadButton = el("button", ~cls="btn brw-load", ~text="Load", ~parent=foot)

  // the search result and the selection in it
  let results = ref([])
  let selected: ref<option<Library.entry>> = ref(None)
  let rows: ref<array<(Library.entry, element)>> = ref([])
  let sameEntry = (a: Library.entry, b: Library.entry) => a.source === b.source && a.index == b.index

  let previewTimer = ref(None)
  let schedulePreview = (e: Library.entry) =>
    if previewOn(t) {
      previewTimer.contents->Option.forEach(clearTimeout)
      previewTimer :=
        Some(
          setTimeout(() => {
            previewTimer := None
            programs->ProgramStore.preview(e.preset)
            previewed := true
          }, 60),
        )
    }

  let close = () => {
    previewTimer.contents->Option.forEach(clearTimeout)
    t.refresh = None
    t.addFiles = None
    shade->remove
  }

  let cancel = () => {
    previewTimer.contents->Option.forEach(clearTimeout)
    if previewed.contents {
      programs->ProgramStore.restore(kept)
    }
    close()
  }

  let commit = () =>
    selected.contents->Option.forEach(e => {
      previewTimer.contents->Option.forEach(clearTimeout)
      switch e.source.kind {
      | Bank =>
        programs->ProgramStore.keep(kept)
        programs->ProgramStore.select(e.index, ~keepEdits=false)
      | Bundled | Cached | File =>
        programs->ProgramStore.loadIntoCurrent(e.preset)
        ctx.toast(`Loaded "${Preset.name(e.preset)}" into program ${ProgramStore.number(programs.current)}`)
      }
      close()
    })

  let render = ref(() => ())
  let rerender = () => render.contents()

  let addFiles = files =>
    readFiles(t, files)
    ->Promise.thenResolve(added => {
      switch added {
      | [one] => t.filters = {...t.filters, source: Some(one.id)}
      | [] => ()
      | _ => t.filters = {...t.filters, source: None}
      }
      rerender()
    })
    ->Promise.ignore

  let openFiles = FilePicker.makeMultiple(root, ~accept=Preset.extensions->Array.join(","), addFiles)

  let setFilters = f => {
    t.filters = f
    rerender()
  }
  let toggleFacet = (facet, value) => setFilters(t.filters->Library.toggleFacet(facet, value))

  // a tag chip: click it to filter by the tag
  let chip = (parent, label, key, ~on) => {
    let c = el("span", ~cls=on ? "brw-chip on" : "brw-chip", ~text=label, ~parent)
    c->onMouse(#click, ev => {
      ev->stopPropagation
      toggleFacet(Tag, key)
    })
    c
  }

  //==============================================================================
  // details

  let renderInfo = () => {
    info->setTextContent("")
    switch selected.contents {
    | None => el("div", ~cls="brw-empty", ~text="Pick a preset to see its details.", ~parent=info)->ignore
    | Some({source, index, preset}) =>
      let meta = preset.meta
      el("div", ~cls="brw-iname", ~text=meta.name == "" ? "(no name)" : meta.name, ~parent=info)->ignore
      let line = [
        meta.author != "" ? Some("by " ++ meta.author) : None,
        meta.category != "" ? Some(meta.category) : None,
        Some(source.kind == Bank ? `program ${ProgramStore.number(index)} in this bank` : source.name),
      ]->Array.filterMap(x => x)
      el("div", ~cls="brw-isub", ~text=line->Array.join(" · "), ~parent=info)->ignore
      if meta.tags != [] {
        let tags = el("div", ~cls="brw-itags", ~parent=info)
        meta.tags->Array.forEach(tag =>
          chip(tags, tag, Library.norm(tag), ~on=t.filters.tags->Array.includes(Library.norm(tag)))->ignore
        )
      }
      if meta.description != "" {
        el("div", ~cls="brw-idesc", ~text=meta.description, ~parent=info)->ignore
      }
      let macros =
        meta.macroNames
        ->Array.mapWithIndex((name, i) => name == "" ? None : Some(`${Int.toString(i + 1)} ${name}`))
        ->Array.filterMap(x => x)
      if macros != [] {
        el("div", ~cls="brw-ihead", ~text="macros", ~parent=info)->ignore
        el("div", ~cls="brw-itext", ~text=macros->Array.join(" · "), ~parent=info)->ignore
      }
      let extras = Preset.porridgeOnly(preset)->Array.filter(x => x != "the full name")
      if extras != [] {
        el("div", ~cls="brw-ihead", ~text="beyond Oatmeal", ~parent=info)->ignore
        el("div", ~cls="brw-itext", ~text=extras->Array.join(", "), ~parent=info)->ignore
      }
    }
  }

  let updateLoadButton = () => {
    let label = switch selected.contents {
    | Some({source: {kind: Bank}, index}) if index == programs.current => "Keep program " ++ ProgramStore.number(index)
    | Some({source: {kind: Bank}, index}) => "Go to program " ++ ProgramStore.number(index)
    | Some(_) => "Load into program " ++ ProgramStore.number(programs.current)
    | None => "Load"
    }
    loadButton->setTextContent(label)
    loadButton->toggleClass("off", selected.contents == None)
  }

  let choose = (e: Library.entry, ~play) => {
    selected := Some(e)
    rows.contents->Array.forEach(((r, row)) => row->toggleClass("sel", sameEntry(r, e)))
    renderInfo()
    updateLoadButton()
    if play {
      schedulePreview(e)
    }
  }

  let scrollToSelected = () =>
    selected.contents->Option.forEach(e =>
      rows.contents
      ->Array.find(((r, _)) => sameEntry(r, e))
      ->Option.forEach(((_, row)) => {
        let top = row->offsetTop
        let bottom = top + row->offsetHeight
        let viewTop = list->scrollTop
        let viewHeight = list->clientHeight
        if top < viewTop {
          list->setScrollTop(top)
        } else if bottom > viewTop + viewHeight {
          list->setScrollTop(bottom - viewHeight)
        }
      })
    )

  let move = delta => {
    let found = results.contents
    if found != [] {
      let at = switch selected.contents {
      | Some(e) => found->Array.findIndex(r => sameEntry(r, e))
      | None => -1
      }
      let shown = Math.Int.min(Array.length(found), maxRows)
      let next = at < 0 ? 0 : Math.Int.max(0, Math.Int.min(shown - 1, at + delta))
      if next != at {
        choose(found->Array.getUnsafe(next), ~play=true)
        scrollToSelected()
      }
    }
  }

  //==============================================================================
  // sidebar: sources, then the facets

  let renderSide = (all, q) => {
    side->setTextContent("")
    let heading = text => el("div", ~cls="brw-shead", ~text, ~parent=side)->ignore
    let row = (label, n, ~on, ~cls="", onClick) => {
      let r = el("div", ~cls="brw-srow" ++ (on ? " on" : "") ++ cls, ~parent=side)
      el("span", ~cls="brw-slabel", ~text=label, ~parent=r)->ignore
      el("span", ~cls="brw-n", ~text=n, ~parent=r)->ignore
      r->onMouse(#click, _ => onClick())
      r
    }

    heading("sources")
    let countIn = (source: option<Library.source>) =>
      all
      ->Array.filter((e: Library.entry) =>
        source->Option.mapOr(true, s => e.source === s) &&
          Library.matches(e, q, {...t.filters, source: None})
      )
      ->Array.length
    row("All", Int.toString(countIn(None)), ~on=t.filters.source == None, () =>
      setFilters({...t.filters, source: None})
    )->ignore
    sources(t)->Array.forEach(s => {
      let n = switch s.status {
      | Loading => "…"
      | Failed(_) => "–"
      | Ready => Int.toString(countIn(Some(s)))
      }
      let bank = s.kind == Cached ? bankOf(t, s) : None
      let opened = s.kind == File || s.kind == Cached && bank->Option.mapOr(true, b => b.origin == Opened)
      let r = row(s.name, n, ~on=t.filters.source == Some(s.id), ~cls=opened ? " file" : "", () =>
        setFilters({...t.filters, source: Some(s.id)})
      )
      switch (s.status, bank) {
      | (Failed(e), _) =>
        r->addClass("bad")
        r->setAttribute("title", Str(`Couldn't read it: ${e}`))
      | (_, Some({origin: Folder, path})) => r->setAttribute("title", Str(path))
      | (_, _) if s.kind == Cached => r->setAttribute("title", Str("Opened here before; the plugin keeps it"))
      | _ => ()
      }
      if opened {
        let x = el("span", ~cls="brw-srm", ~text="✕", ~parent=r)
        x->setAttribute("title", Str(s.kind == Cached ? "Forget this file" : "Close this file"))
        x->onMouse(#click, ev => {
          ev->stopPropagation
          t.opened = t.opened->Array.filter(o => o !== s)
          if s.kind == Cached {
            t.cached = t.cached->Array.filter(((c, _)) => c !== s)
            bank->Option.forEach(b => t.library->BankLibrary.remove(b.id))
          }
          if t.filters.source == Some(s.id) {
            t.filters = {...t.filters, source: None}
          }
          selected.contents->Option.forEach(e =>
            if e.source === s {
              selected := None
            }
          )
          rerender()
        })
      }
    })
    let add = el("div", ~cls="brw-srow brw-open", ~text="+ open files…", ~parent=side)
    add->onMouse(#click, _ => openFiles())

    // the folders the plugin looks in for banks
    let library = t.library
    if library.available {
      heading("bank folders")
      library
      ->BankLibrary.folders
      ->Array.forEach(folder => {
        let r = el("div", ~cls="brw-srow brw-folder", ~parent=side)
        let name = folder->String.split("/")->Array.flatMap(String.split(_, "\\"))->Array.findLast(p => p != "")
        el("span", ~cls="brw-slabel", ~text=name->Option.getOr(folder), ~parent=r)->ignore
        r->setAttribute("title", Str(folder))
        let x = el("span", ~cls="brw-srm", ~text="✕", ~parent=r)
        x->setAttribute("title", Str("Stop looking in this folder"))
        x->onMouse(#click, ev => {
          ev->stopPropagation
          library->BankLibrary.removeFolder(folder)
        })
      })
      let folderInput = el("input", ~cls="brw-addfolder", ~parent=side)
      folderInput->setPlaceholder("+ add a folder: paste its path")
      folderInput->setSpellcheck(false)
      folderInput->onKeyDown(k => {
        k->stopPropagation
        switch k->key {
        | "Enter" =>
          library->BankLibrary.addFolder(folderInput->value)
          folderInput->setValue("")
        | "Escape" => folderInput->setValue("")
        | _ => ()
        }
      })
      if library->BankLibrary.folders != [] {
        let rescan = el(
          "div",
          ~cls="brw-srow brw-open",
          ~text=library.scanning ? "looking for banks…" : "↻ look again",
          ~parent=side,
        )
        rescan->setAttribute("title", Str("Look through the folders for new and changed banks"))
        rescan->onMouse(#click, _ => library->BankLibrary.scan)
      }
    }

    let facet = (title, which: Library.facet, picked) => {
      let values = Library.facetCounts(all, q, t.filters, which)
      if values != [] {
        heading(title)
        let wrap = el("div", ~cls=which == Tag ? "brw-chips" : "brw-facet", ~parent=side)
        values->Array.forEach(((key, label, n)) => {
          let on = picked->Array.includes(key)
          let c = el("span", ~cls=on ? "brw-fv on" : "brw-fv", ~parent=wrap)
          el("span", ~text=label, ~parent=c)->ignore
          el("span", ~cls="brw-n", ~text=Int.toString(n), ~parent=c)->ignore
          c->onMouse(#click, _ => toggleFacet(which, key))
        })
      }
    }
    facet("categories", Category, t.filters.categories)
    facet("tags", Tag, t.filters.tags)
    facet("authors", Author, t.filters.authors)
  }

  //==============================================================================
  // the list

  render :=
    () => {
      // the bank's empty slots only show when it is listed on its own
      let emptySlots =
        t.filters.source == Some(t.bank.id) && t.text == "" && !Library.hasFacets(t.filters)
      let all = Library.entries(sources(t), ~emptySlots)
      let q = Library.parse(t.text)
      let found = Library.search(all, q, t.filters)
      results := found
      renderSide(all, q)

      let total = Array.length(found)
      count->setTextContent(
        total == 1 ? "1 preset" : Int.toString(total) ++ " presets",
      )
      clearText->toggleClass("on", t.text != "" || Library.hasFacets(t.filters))

      list->setTextContent("")
      let showSource = t.filters.source == None
      list->toggleClass("nosrc", !showSource)
      rows :=
        found
        ->Array.slice(~start=0, ~end=maxRows)
        ->Array.map(e => {
          let r = el("div", ~cls="brw-row", ~parent=list)
          let isCurrent = e.source.kind == Bank && e.index == programs.current
          r->toggleClass("cur", isCurrent)
          el("span", ~cls="brw-num", ~text=e.source.kind == Bank ? ProgramStore.number(e.index) : "", ~parent=r)->ignore
          el("span", ~cls="brw-name", ~text=e.preset.meta.name == "" ? "(no name)" : e.preset.meta.name, ~parent=r)->ignore
          el("span", ~cls="brw-cat", ~text=e.preset.meta.category, ~parent=r)->ignore
          let tags = el("span", ~cls="brw-tags", ~parent=r)
          e.preset.meta.tags->Array.forEach(tag => {
            let key = Library.norm(tag)
            chip(tags, tag, key, ~on=t.filters.tags->Array.includes(key))->ignore
          })
          if showSource {
            el("span", ~cls="brw-src", ~text=e.source.name, ~parent=r)->ignore
          }
          r->onMouse(#click, _ => choose(e, ~play=true))
          r->onMouse(#dblclick, _ => {
            choose(e, ~play=false)
            commit()
          })
          (e, r)
        })

      if total > maxRows {
        el(
          "div",
          ~cls="brw-more",
          ~text=`${Int.toString(total - maxRows)} more: narrow the search to see them`,
          ~parent=list,
        )->ignore
      }
      if total == 0 {
        let loading = sources(t)->Array.some(s => s.status == Loading)
        let msg = el("div", ~cls="brw-none", ~parent=list)
        el(
          "div",
          ~text=loading && Library.isEmptyQuery(q) ? "Reading the bundled banks…" : "Nothing matches.",
          ~parent=msg,
        )->ignore
        if t.text != "" || Library.hasFacets(t.filters) || t.filters.source != None {
          let b = el("button", ~cls="btn", ~text="Show everything", ~parent=msg)
          b->onMouse(#click, _ => {
            t.text = ""
            input->setValue("")
            setFilters(Library.noFilters)
          })
        }
      }

      // keep the selection if it is still there
      selected :=
        selected.contents->Option.flatMap(e =>
          found->Array.slice(~start=0, ~end=maxRows)->Array.find(r => sameEntry(r, e))
        )
      selected.contents->Option.forEach(e =>
        rows.contents->Array.forEach(((r, row)) => row->toggleClass("sel", sameEntry(r, e)))
      )
      renderInfo()
      updateLoadButton()
    }

  //==============================================================================
  // events

  let updatePreviewToggle = () => previewToggle->toggleClass("on", previewOn(t))
  previewToggle->onMouse(#click, _ => {
    t.settings->Settings.save(previewSetting, Boolean(!previewOn(t)))
    updatePreviewToggle()
  })
  updatePreviewToggle()

  let onInput = () => {
    t.text = input->value
    rerender()
    // a new search starts at its best match
    switch (selected.contents, results.contents[0]) {
    | (None, Some(first)) if t.text != "" => choose(first, ~play=false)
    | _ => ()
    }
  }
  input->onEvent(#input, _ => onInput())
  clearText->onMouse(#click, _ => {
    t.text = ""
    input->setValue("")
    setFilters({...Library.noFilters, source: t.filters.source})
    input->focus
  })

  cancelButton->onMouse(#click, _ => cancel())
  loadButton->onMouse(#click, _ => commit())

  // keys stay in the browser (the host may otherwise take them as shortcuts)
  root->onKeyDown(k => {
    k->stopPropagation
    switch k->key {
    | "ArrowDown" =>
      k->preventDefault
      move(1)
    | "ArrowUp" =>
      k->preventDefault
      move(-1)
    | "PageDown" =>
      k->preventDefault
      move(10)
    | "PageUp" =>
      k->preventDefault
      move(-10)
    | "Enter" => commit()
    | "Escape" =>
      if input->value != "" {
        t.text = ""
        input->setValue("")
        rerender()
      } else {
        cancel()
      }
    | _ => ()
    }
  })
  // typing always goes to the search
  root->onPointer(#pointerup, ev =>
    switch ev->originalTarget->tagNameOf {
    | Some("INPUT") => ()
    | _ => input->focus
    }
  )
  shade->Dialog.closeOnShade(cancel)

  t.refresh = Some(rerender)
  t.addFiles = Some(addFiles)
  rerender()

  // start on the current program
  results.contents
  ->Array.find(e => e.source.kind == Bank && e.index == programs.current)
  ->Option.forEach(e => {
    choose(e, ~play=false)
    scrollToSelected()
  })
  input->focus
  input->select
}

let addFiles = (t, files) => t.addFiles->Option.forEach(fn => fn(files))
