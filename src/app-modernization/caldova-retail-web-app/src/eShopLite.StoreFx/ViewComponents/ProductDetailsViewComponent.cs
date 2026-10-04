using System;

using Microsoft.AspNetCore.Mvc;

using eShopLite.StoreFx.Services;

namespace eShopLite.StoreFx.ViewComponents
{
    // Replaces the old [ChildActionOnly] HomeController.ProductDetails child action.
    // Output caching is applied at the call site via the <cache> tag helper.
    public class ProductDetailsViewComponent : ViewComponent
    {
        private readonly IStoreService _service;

        public ProductDetailsViewComponent(IStoreService service)
        {
            _service = service ?? throw new ArgumentNullException(nameof(service));
        }

        public IViewComponentResult Invoke(int id)
        {
            var product = _service.GetProduct(id);
            if (product == null)
            {
                return Content(string.Empty);
            }

            return View(product);
        }
    }
}
