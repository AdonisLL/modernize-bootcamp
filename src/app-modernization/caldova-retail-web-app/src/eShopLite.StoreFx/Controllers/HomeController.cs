using System;

using Microsoft.AspNetCore.Mvc;

using eShopLite.StoreFx.Services;

namespace eShopLite.StoreFx.Controllers
{
    public class HomeController : Controller
    {
        private readonly IStoreService _service;

        public HomeController(IStoreService service)
        {
            _service = service ?? throw new ArgumentNullException(nameof(service));
        }

        public IActionResult Index()
        {
            return View();
        }

        public IActionResult Products(string q)
        {
            ViewBag.Message = "This component demonstrates showing products data";
            ViewBag.SearchTerm = q;

            var products = _service.SearchProducts(q);

            return View(products);
        }

        public IActionResult Product(int id)
        {
            var product = _service.GetProduct(id);

            if (product == null)
            {
                return NotFound();
            }

            return View(product);
        }

        public IActionResult Stores()
        {
            ViewBag.Message = "This component demonstrates showing stores data";

            var stores = _service.GetStores();

            return View(stores);
        }

        [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
        public IActionResult Error()
        {
            return View();
        }
    }
}
