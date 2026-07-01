// ── Rebirth developer product ──────────────────────────────────────────────────
// The Robux "Safe Rebirth" sold on RebirthMenu/ButtonsFrame/SafeRebirthButton.
// Unlike a normal rebirth (which resets Money + stat levels), the safe rebirth
// keeps ALL progression — only Rebirths is incremented (MultRebirth grows) and the
// pad rocket is swapped to the new rebirth level. Single source of truth shared by
// both sides:
//   • client (RebirthMenuController) prompts this product on the SafeRebirthButton.
//   • server (MoneyProductService.ProcessReceipt) grants it via RebirthService.safeRebirth.
// The Robux price is configured per product on the Roblox dashboard, not here.

export const SAFE_REBIRTH_PRODUCT_ID = 3607580555;

// True if the purchased productId is the safe-rebirth product. Server-side lookup,
// mirrors amountForProduct / levelGrantForProduct so ProcessReceipt stays symmetric.
export function isSafeRebirthProduct(productId: number): boolean {
	return productId === SAFE_REBIRTH_PRODUCT_ID;
}
