// Porridge patch view entry point (Cmajor calls the default export with a PatchConnection).

import { PorridgeView } from "./view.js";

export default function createPatchView (patchConnection)
{
    if (! window.customElements.get ("porridge-view"))
        window.customElements.define ("porridge-view", PorridgeView);

    const view = document.createElement ("porridge-view");
    view.init (patchConnection);
    return view;
}
