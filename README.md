# Afya Njia app · Pharmacy v0.1 (iPhone)

Flutter app for the counter: PIN login and counter sale, talking to the Afya Njia API.

You need a Mac with **Xcode** installed (from the App Store) to build for iPhone. Apple only allows iPhone apps to be built on macOS.

## 1. Create the Flutter project

```bash
cd ~
flutter create --org tz.co.saola --platforms ios,android afya_njia_app
cd afya_njia_app
flutter pub add http flutter_secure_storage
```

## 2. Copy in the Afya Njia code

```bash
mkdir -p ~/afya-app-src
unzip ~/Downloads/afya_njia_app-v0.1.zip -d ~/afya-app-src
cp -R ~/afya-app-src/afya_njia_app/lib/. lib/
rm test/widget_test.dart     # Flutter's sample test refers to the demo app we replaced
flutter analyze              # should say "No issues found!"
```

## 3. Let the iPhone talk to your Mac over plain HTTP

iOS blocks unencrypted `http://` connections by default (App Transport Security). During development the server on your Mac has no HTTPS yet, so open `ios/Runner/Info.plist` and add these lines just before the final `</dict>`:

```xml
<!-- DEVELOPMENT ONLY: remove when the API has HTTPS -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
<key>NSLocalNetworkUsageDescription</key>
<string>Afya Njia inaunganisha na seva ya duka kwenye mtandao huu.</string>
```

The second key is the sentence iOS shows when it asks permission to reach devices on the local Wi-Fi (your Mac). Tap **Allow** the first time.

**Before the real pilot**, the API must be on a server with HTTPS, and the `NSAppTransportSecurity` block must be removed. An app that allows arbitrary loads would also be questioned by App Store review.

## 4. Run in the iOS Simulator (quickest check)

Terminal 1, in `~/afya-api`:
```bash
php artisan serve
```

Terminal 2, in `~/afya_njia_app`:
```bash
open -a Simulator
flutter run
```

The Simulator shares your Mac's network, so the default address `http://127.0.0.1:8000/api` works. Sign in as the helper with PIN 5678.

## 5. Run on a real iPhone

1. **Start the API so other devices can reach it**: `php artisan serve --host=0.0.0.0 --port=8000`
2. **Find your Mac's Wi-Fi IP**: `ipconfig getifaddr en0` (e.g. `192.168.1.20`). The iPhone must be on the same Wi-Fi.
3. **Signing**: `open ios/Runner.xcworkspace`, select **Runner** › **Signing & Capabilities**, choose your Apple ID as **Team**. If Xcode complains the bundle identifier is taken, change it slightly (e.g. `tz.co.saola.afyanjia.dev`).
4. **On the iPhone**: plug it into the Mac, tap **Trust**, and turn on **Settings › Privacy & Security › Developer Mode** (it restarts).
5. **Run** from `~/afya_njia_app`:
   ```bash
   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000/api
   ```
6. The first time, the iPhone may refuse to open the app. Go to **Settings › General › VPN & Device Management**, tap your Apple ID, and tap **Trust**.

**Free Apple ID limit:** apps installed this way stop opening after 7 days and must be re-installed from the Mac. That's fine for testing with your friend beside you. For a real pilot he can update himself, use the paid Apple Developer Program and **TestFlight**.

## How the app is built (read in this order)

| File | What it does | Why it's built this way |
|---|---|---|
| `lib/config.dart` | Server address, pharmacy id | Set with `--dart-define` at build time, so you never edit code to switch between Simulator, iPhone and the real server. |
| `lib/core/api_client.dart` | All HTTP calls | Headers, token, 15-second timeout and error handling written **once**. Screens get data or an `ApiException` with a ready-to-show Swahili message. |
| `lib/core/session.dart` | Who is signed in | A `ChangeNotifier`: when login state changes it notifies listeners and the app redraws. The token lives in the Keychain, not plain storage. |
| `lib/main.dart` | App start, theme, the "gate" | `ListenableBuilder` shows the PIN screen or the home screen depending on the session. Also closes open screens if the token expires. |
| `lib/core/ids.dart` | Random ids made on the phone | Used for the phone's id and each sale's id, so the server can recognise retries. |
| `lib/core/money.dart` | `formatTsh(12500)` → `TSh 12,500` | Money is an `int` everywhere, same as the server. No floating-point rounding. |
| `lib/models/` | `Staff`, `Product` | Turn JSON from the API into typed Dart objects, so typos become compile errors instead of crashes. |
| `lib/features/auth/pin_screen.dart` | Screen 5: pick person, 4-digit PIN | The 4th digit submits automatically, saving a tap many times a day. Wrong PIN clears and shows the server's message. |
| `lib/features/sale/cart.dart` | The basket's rules | Plain Dart, no widgets: can't add beyond stock, totals, the request body. Each basket carries a sale id made on the phone; if the network drops mid-sale the basket freezes and "Tuma tena" resends the same id, so a sale can never count twice. |
| `lib/features/sale/counter_screen.dart` | Screen 2: search and add | Results get the whole screen; the basket is one slim bar at the bottom ("Kikapu · 2 bidhaa · TSh 600 · Lipa"), and rows already in it show − 2 + right on the row (tap the number to type an exact amount, e.g. 21). The list never re-orders, so the next tap always lands on the same medicine. Search waits for a 300 ms pause in typing. A misspelled search shows the closest product under "Je, ulimaanisha…?" with an amber border; it is only added when tapped. Leaving with a full basket asks first. |
| `lib/features/sale/quantity_dialog.dart` | "How many?" keypad | Type 21 instead of tapping + 20 times. Checks stock before closing; 0 removes the item. |
| `lib/features/sale/checkout_screen.dart` | Checkout | The full basket, quantities, discount, payment and "Kamilisha". Shares the same Cart object as the search screen. Network-uncertain sales freeze here with "Tuma tena". |
| `lib/features/home/home_screen.dart` | After login (v0.2 "Mint Laini") | Money hidden by default (TSh ••••••) because the phone faces customers; the eye shows it and the choice is remembered. Owner: today's sales with a ring for the daily goal (tap the ring to set it), payment split, four tiles (Uza, Zamu, Muda, Kuagiza), the week/month chart and the latest 4 sales. Alerts live behind the bell; rarely used screens behind **Zaidi**, including Toka. Helper: his own sales only, Uza and Zamu. |
| `lib/features/home/widgets/` | Home pieces | `target_ring.dart` (a CustomPainter: round-ended arc), `trend_card.dart` (loads `dashboard/trend` itself, caches week and month so switching is instant), `recent_sales_card.dart` (one card for the owner's and the helper's sales). |
| `lib/features/sales/sales_list_screen.dart` | Today's sales | Owner sees everyone's, a helper only his own (the server decides). Tap a sale for its lines; "Futa" cancels it with a required reason. Cancelled sales stay, crossed out. |
| `lib/features/shift/shift_screen.dart` | Shift and cash | Open with the cash in the drawer. While open: sales, payment split, cash expected in the drawer, and what needs attention. Close by counting the drawer; the gap shows live while typing and needs a reason if not zero. |
| `lib/features/expiry/expiry_screen.dart` | Expiry alerts | Groups that don't overlap: already expired, 1–30, 31–60, 61–90 days, each with a count, the money at risk and what to do. One request, grouped on the phone. Owner only. |
| `lib/features/stock/stock_alerts_screen.dart` | What to reorder | "Zimeisha (hazipo)" (0 in stock) kept apart from "Zinakaribia kuisha" (at or below the reorder level). Owner only. |
| `lib/core/format.dart`, `lib/core/dialogs.dart` | Shared helpers | Times in local time, Swahili "time ago", dates and greetings, tolerant number reading; a text dialog that owns its controller (avoids the "used after disposed" crash). |

## Next steps

1. Receive stock screen (supplier deliveries after the first import)
2. Server online with HTTPS, then TestFlight / APK for the pilot phones
