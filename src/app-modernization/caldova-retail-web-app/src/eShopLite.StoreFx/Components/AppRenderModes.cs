using Microsoft.AspNetCore.Components;
using Microsoft.AspNetCore.Components.Web;

namespace eShopLite.StoreFx.Components
{
    public static class AppRenderModes
    {
        // Interactive Server without prerendering: components render once the circuit is
        // connected, so JS interop (browser storage) is available in OnInitializedAsync and
        // database reads run only once. This also avoids prerender/interactive flicker.
        public static readonly IComponentRenderMode InteractiveServerNoPrerender =
            new InteractiveServerRenderMode(prerender: false);
    }
}
