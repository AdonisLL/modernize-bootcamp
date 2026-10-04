using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;

using eShopLite.StoreFx.Services;

namespace eShopLite.StoreFx.Controllers
{
    public class CartController : Controller
    {
        private readonly IStoreService _storeService;
        private readonly ICartService _cartService;
        private readonly IOrderService _orderService;

        public CartController(IStoreService storeService, ICartService cartService, IOrderService orderService)
        {
            _storeService = storeService ?? throw new System.ArgumentNullException(nameof(storeService));
            _cartService = cartService ?? throw new System.ArgumentNullException(nameof(cartService));
            _orderService = orderService ?? throw new System.ArgumentNullException(nameof(orderService));
        }

        public ActionResult Index()
        {
            var cart = _cartService.GetCart();

            return View(cart);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Add(int productId, int quantity = 1, string returnUrl = null)
        {
            var product = _storeService.GetProduct(productId);
            if (product == null)
            {
                return NotFound();
            }

            if (quantity < 1)
            {
                quantity = 1;
            }

            var cart = _cartService.GetCart();
            cart.Add(product, quantity);
            _cartService.Save(cart);

            TempData["CartMessageKind"] = "success";
            TempData["CartMessage"] = string.Format("Added {0} \u00d7 \"{1}\" to your cart.", quantity, product.Name);

            return RedirectBack(returnUrl);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult UpdateQuantity(int productId, int quantity)
        {
            var product = _storeService.GetProduct(productId);
            if (product == null)
            {
                return NotFound();
            }

            var cart = _cartService.GetCart();
            cart.SetQuantity(productId, quantity);
            _cartService.Save(cart);

            return RedirectToAction("Index");
        }

        private ActionResult RedirectBack(string returnUrl)
        {
            if (!string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl))
            {
                return Redirect(returnUrl);
            }

            return RedirectToAction("Index");
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Remove(int productId)
        {
            var cart = _cartService.GetCart();
            cart.Remove(productId);
            _cartService.Save(cart);

            return RedirectToAction("Index");
        }

        [Authorize]
        public ActionResult Checkout()
        {
            var cart = _cartService.GetCart();
            if (cart.IsEmpty)
            {
                return RedirectToAction("Index");
            }

            return View(cart);
        }

        [Authorize]
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult PlaceOrder()
        {
            var cart = _cartService.GetCart();
            if (cart.IsEmpty)
            {
                return RedirectToAction("Index");
            }

            var order = _orderService.PlaceOrder(cart, User.Identity.Name);
            _cartService.Clear();

            return RedirectToAction("Confirmation", new { id = order.Id });
        }

        [Authorize]
        public ActionResult Confirmation(int id)
        {
            var order = _orderService.GetOrder(id, User.Identity.Name);
            if (order == null)
            {
                return NotFound();
            }

            return View(order);
        }
    }
}

