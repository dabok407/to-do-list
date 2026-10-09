package com.dabok407.hangeoreum

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.util.Base64
import com.android.billingclient.api.*
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec

/** Store-owned active subscriptions; never infer a year of access from purchaseTime. */
class SubscriptionBridge(private val activity: Activity, messenger: BinaryMessenger) : PurchasesUpdatedListener {
    private val id = "hangeoreum_pro_yearly"
    private val channel = MethodChannel(messenger, "com.dabok407.hangeoreum/billing")
    private var purchaseResult: MethodChannel.Result? = null
    private var connecting = false
    private val ready = mutableListOf<() -> Unit>()
    private val failed = mutableListOf<(String) -> Unit>()
    private val client = BillingClient.newBuilder(activity).setListener(this)
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection().build()

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "manage") {
                try {
                    activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/account/subscriptions?sku=$id&package=${activity.packageName}")))
                    result.success(null)
                } catch (_: Exception) { result.error("manage", "구독 관리 화면을 열 수 없어요.", null) }
            } else if (call.method in listOf("status", "restore", "purchase")) {
                connect({
                    if (call.method == "purchase") purchase(result) else status(result)
                }, { result.error("store", it, null) })
            } else result.notImplemented()
        }
    }

    private fun connect(action: () -> Unit, error: (String) -> Unit) {
        if (client.isReady) { action(); return }
        ready.add(action); failed.add(error)
        if (connecting) return
        connecting = true
        client.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                connecting = false
                val actions = ready.toList(); val errors = failed.toList()
                ready.clear(); failed.clear()
                if (result.responseCode == BillingClient.BillingResponseCode.OK) actions.forEach { it() }
                else errors.forEach { it("Google Play에 연결하지 못했어요.") }
            }
            override fun onBillingServiceDisconnected() { connecting = false }
        })
    }

    private fun product(callback: (ProductDetails?, String?) -> Unit) {
        val params = QueryProductDetailsParams.newBuilder().setProductList(listOf(
            QueryProductDetailsParams.Product.newBuilder().setProductId(id).setProductType(BillingClient.ProductType.SUBS).build()
        )).build()
        client.queryProductDetailsAsync(params) { response, details ->
            activity.runOnUiThread {
                if (response.responseCode != BillingClient.BillingResponseCode.OK) callback(null, "스토어 상품을 조회하지 못했어요.")
                else callback(details.productDetailsList.firstOrNull { it.productId == id }, null)
            }
        }
    }

    // Only the one-year, auto-renewing base plan, without introductory offers.
    private fun annualOffer(p: ProductDetails) = p.subscriptionOfferDetails?.firstOrNull { offer ->
        offer.basePlanId == "annual" && offer.offerId == null &&
            offer.pricingPhases.pricingPhaseList.size == 1 &&
            offer.pricingPhases.pricingPhaseList.first().let {
                it.billingPeriod == "P1Y" && it.recurrenceMode == ProductDetails.RecurrenceMode.INFINITE_RECURRING
            }
    }

    private fun verified(p: Purchase): Boolean {
        if (BuildConfig.PLAY_BILLING_PUBLIC_KEY.isBlank()) return false
        return try {
            val key = KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(Base64.decode(BuildConfig.PLAY_BILLING_PUBLIC_KEY, Base64.DEFAULT)))
            Signature.getInstance("SHA1withRSA").run {
                initVerify(key); update(p.originalJson.toByteArray(Charsets.UTF_8)); verify(Base64.decode(p.signature, Base64.DEFAULT))
            }
        } catch (_: Exception) { false }
    }

    private fun status(result: MethodChannel.Result, message: String? = null) {
        if (BuildConfig.PLAY_BILLING_PUBLIC_KEY.isBlank()) {
            result.error("configuration", "스토어 상품 등록 후 구독을 시작할 수 있어요.", null)
            return
        }
        client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.SUBS).build()) { response, purchases ->
            activity.runOnUiThread {
                if (response.responseCode != BillingClient.BillingResponseCode.OK) {
                    result.error("status", "구독 확인을 위해 Google Play에 다시 연결해주세요.", null); return@runOnUiThread
                }
                val owned = purchases.firstOrNull { id in it.products && !it.isSuspended && it.purchaseState == Purchase.PurchaseState.PURCHASED && verified(it) }
                val pending = purchases.any { id in it.products && it.purchaseState == Purchase.PurchaseState.PENDING }
                fun deliver(ackError: Boolean = false) {
                    // A failed acknowledgement is not a verified revocation.
                    if (ackError) {
                        result.error("acknowledgement", "결제 확인을 마치지 못했어요. 구매 복원으로 다시 확인해주세요.", null)
                        return
                    }
                    product { p, error ->
                        val offer = p?.let { annualOffer(it) }
                        result.success(mapOf(
                            "active" to (owned != null && !ackError), "pending" to pending,
                            "available" to (offer != null && BuildConfig.PLAY_BILLING_PUBLIC_KEY.isNotBlank()),
                            "price" to offer?.pricingPhases?.pricingPhaseList?.firstOrNull()?.formattedPrice,
                            "autoRenewing" to owned?.isAutoRenewing,
                            "message" to (if (ackError) "결제 확인을 마치지 못했어요. 구매 복원을 눌러 다시 확인해주세요."
                                else message ?: error ?: if (BuildConfig.PLAY_BILLING_PUBLIC_KEY.isBlank() || offer == null) "스토어 상품 등록 후 구독을 시작할 수 있어요." else null)
                        ))
                    }
                }
                if (owned != null && !owned.isAcknowledged) {
                    client.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(owned.purchaseToken).build()) {
                        activity.runOnUiThread { deliver(it.responseCode != BillingClient.BillingResponseCode.OK) }
                    }
                } else deliver()
            }
        }
    }

    private fun purchase(result: MethodChannel.Result) {
        if (purchaseResult != null) { result.error("busy", "결제가 진행 중이에요.", null); return }
        if (BuildConfig.PLAY_BILLING_PUBLIC_KEY.isBlank()) { status(result); return }
        purchaseResult = result
        product { p, error ->
            val offer = p?.let { annualOffer(it) }
            if (p == null || offer == null) {
                purchaseResult = null; result.error("product", error ?: "연간 구독 상품을 사용할 수 없어요.", null)
            } else {
                val response = client.launchBillingFlow(activity, BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(
                    BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(p).setOfferToken(offer.offerToken).build()
                )).build())
                if (response.responseCode != BillingClient.BillingResponseCode.OK) {
                    purchaseResult = null; status(result, "결제를 시작하지 못했어요. 구매 복원을 확인해주세요.")
                }
            }
        }
    }

    override fun onPurchasesUpdated(response: BillingResult, purchases: MutableList<Purchase>?) {
        activity.runOnUiThread {
            val result = purchaseResult
            purchaseResult = null
            if (result != null) {
                status(result, when (response.responseCode) {
                    BillingClient.BillingResponseCode.OK -> null
                    BillingClient.BillingResponseCode.USER_CANCELED -> "결제를 취소했어요."
                    else -> "결제를 완료하지 못했어요. 구매 복원으로 확인해주세요."
                })
            } else channel.invokeMethod("changed", null)
        }
    }

    fun close() { channel.setMethodCallHandler(null); client.endConnection() }
}
