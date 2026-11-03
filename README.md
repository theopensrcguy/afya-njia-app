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
| `lib/features/sale/cart.dart` | The basket's rules | Plain Dart, no widgets: each product sold in one unit (kidonge, kadi or boksi) with that unit's price; stock is checked in base units (2 kadi of 10 = 20 tablets); totals, the request body. Each basket carries a sale id made on the phone; if the network drops mid-sale the basket freezes and "Tuma tena" resends the same id, so a sale can never count twice. |
| `lib/features/sale/counter_screen.dart` | Screen 2: search and add | Results get the whole screen; the basket is one slim bar at the bottom ("Kikapu · 2 bidhaa · TSh 600 · Lipa"), and rows already in it show − 2 + right on the row (tap the number to type an exact amount, e.g. 21). The list never re-orders, so the next tap always lands on the same medicine. Search waits for a 300 ms pause in typing. A misspelled search shows the closest product under "Je, ulimaanisha…?" with an amber border; it is only added when tapped. Leaving with a full basket asks first. Items in the basket that sell in several units show chips (Kidonge · Kadi · Boksi) with each price. |
| `lib/features/sale/scan_screen.dart`, `sell_unit.dart` | Skani + Haraka (v0.8) | The counter shows up to 9 **Haraka** tiles while the search box is empty: what sells most at this time of day, in its usual unit (one tap = one; hold to type a number). The scan button opens the camera and **stays open**: scan, the unit is already chosen (a box barcode offers the kadi inside, because that's what is usually sold), add, scan the next. An unknown code asks once "Ni bidhaa gani?" and every phone knows it after. In Pokea mzigo, the scan button on the search learns the box's barcode for the counter. Needs `flutter pub add mobile_scanner` and a full rebuild. |
| `lib/features/sale/quantity_dialog.dart` | "How many?" keypad | Type 21 instead of tapping + 20 times. Checks stock before closing; 0 removes the item. |
| `lib/features/sale/checkout_screen.dart` | Checkout | The full basket, quantities, discount, payment and "Kamilisha". Shares the same Cart object as the search screen. Network-uncertain sales freeze here with "Tuma tena". |
| `lib/features/home/home_screen.dart` | After login (v0.2 "Mint Laini") | Money hidden by default (TSh ••••••) because the phone faces customers; the eye shows it and the choice is remembered. Owner: today's sales with a ring for the daily goal (tap the ring to set it), payment split, four tiles (Uza, Zamu, Muda, Kuagiza), the week/month chart and the latest 4 sales. Alerts live behind the bell; rarely used screens behind **Zaidi**, including Toka. Helper: his own sales only, Uza and Zamu. |
| `lib/features/home/widgets/` | Home pieces | `target_ring.dart` (a CustomPainter: round-ended arc), `trend_card.dart` (loads `dashboard/trend` itself, caches week and month so switching is instant), `recent_sales_card.dart` (one card for the owner's and the helper's sales). |
| `lib/features/sales/sales_list_screen.dart` | Today's sales | Owner sees everyone's, a helper only his own (the server decides). Tap a sale for its lines; "Futa" cancels it with a required reason. Cancelled sales stay, crossed out. |
| `lib/features/shift/shift_screen.dart` | Shift and cash | Open with the cash in the drawer. While open: sales, payment split, cash expected in the drawer, and what needs attention. Close by counting the drawer; the gap shows live while typing and needs a reason if not zero. |
| `lib/features/expiry/expiry_screen.dart` | Expiry alerts | Groups that don't overlap: already expired, 1–30, 31–60, 61–90 days, each with a count, the money at risk and what to do. One request, grouped on the phone. Owner only. |
| `lib/features/stock/stock_screen.dart` | Hisa (owner, in the bottom bar) | Every product with what's on the shelf ("33 kadi + 6") and its value at cost. The green total follows the chosen chip. Two different problems, two chips: **Muda** = still sellable but expires within 30 days (sell first); **Zimeisha muda** (red, only when there is some) = expired stock still on record (can't be sold: take it off the selling shelf and write it off). The red **Hasara** card opens Zimeisha muda; there each row shows the expired amount and its cost. One request; search and the chips work on the phone. |
| `lib/features/stock/product_stock_screen.dart` | One product | On hand, reorder level (tap to change), units and prices, batches in selling order, and the history of every stock change with who and why. "Rekebisha hisa" removes damaged, lost, expired or returned stock, always with a reason. An expired batch has **Andika kama hasara**: the sheet opens on that batch, reason "Imeisha muda", whole quantity filled in, so writing off is check-and-save. |
| `lib/features/stock/units_editor_screen.dart` | Vipimo | How the product is sold: kidonge 1 · kadi 10 · boksi 100, each with its price. Names are **picked** from a standard list ("Nyingine…" for rare ones), never typed freely, so reports don't split "kadi" / "Kadi " / "strip". The first unit is what stock is counted in. |
| `lib/core/units.dart` | Units helpers | Swahili unit names (tablet → kidonge/vidonge), `describeStock` ("33 kadi + 6"), and joining a sale's batch pieces back into what was sold ("2 kadi"). |
| `lib/core/format.dart`, `lib/core/dialogs.dart` | Shared helpers | Times in local time, Swahili "time ago", dates and greetings, tolerant number reading; a text dialog that owns its controller (avoids the "used after disposed" crash). |

| `lib/features/purchases/receive_screen.dart` | Pokea mzigo | Supplier chips (+ Mpya), optional invoice number and photo, the items, and the total checked against the invoice's total. The owner's delivery counts at once; the helper's is sent for confirmation. A delivery id made on the phone means pressing save again after a network drop never records it twice. |
| `lib/features/purchases/receive_line_screen.dart` | One delivered item | Product, then the packaging this delivery came in (the product's units, last time's packaging, or "+ Nyingine"), how many, batch, expiry as month + year chips, and the price per pack. Pre-filled from what this supplier sent last time; warns on short expiry and on buying above the selling price. |
| `lib/features/purchases/purchases_screen.dart` | Mizigo | Owner: deliveries waiting for confirmation, each with lines, totals vs invoice, the invoice photo (pinch to zoom), and **Kataa** (reason) / **Thibitisha**. Helper: his own deliveries and their status. |
| `lib/features/purchases/new_product_screen.dart` | Bidhaa mpya (v0.7) | Reached from the delivery line's search: your products first, then the catalogue ("+ Mpya"), then "Ongeza … kama bidhaa mpya" for things outside it. The name comes from the catalogue and can't be edited. A yellow **"Je, ni hii unayo tayari?"** card (the server matches by ingredient, so the brand Amoxyl is caught) must be answered before going on: **Ndiyo, ni hiyo** uses the existing product and links the catalogue name to it. Units (base + kadi/boksi with sizes), prices only with edit_prices (otherwise a locked note: the owner sets them), reorder level. |
| `lib/features/purchases/new_product.dart` | The draft | Nothing is created on the phone: the draft travels in the delivery and the server creates the product. Two batches of one new product share one draft. On **Mizigo**, the confirmer sees each new product with price fields and the profit live; **Thibitisha** stays grey until every unit has a price. |

| `lib/features/staff/staff_permissions_screen.dart` | Wafanyakazi na ruhusa (owner) | Each staff member with their permissions. A switch per permission, grouped (Mauzo, Mizigo, Hisa, Fedha, Simu). Switching one on asks **"mpaka lini?"**: today, 3 days, a week, a month, or until changed. One-tap bundles (Msaidizi, Msimamizi) and the full history. **+ Ongeza mfanyakazi** (name + PIN twice); per person ⋮ › Badilisha PIN / Simamisha (signed out everywhere, permissions ended, chosen phones removed; the shop's shared phone is unticked) / Rudisha kazini. |
| `lib/core/permissions.dart`, `lib/models/staff.dart` | Who may do what | `session.user!.can(Perm.viewStock)` decides which tiles, menu items and buttons appear. The list is re-read from `GET me` on every home load. The server enforces everything; the app only hides. |

| `lib/features/auth/change_pin_screen.dart` | Chagua / Badilisha PIN | Forced right after signing in with a temporary PIN (set by the owner); there's no back button, only Toka. Otherwise reachable from Zaidi › Badilisha PIN yangu. Needs the current PIN. |

| `lib/features/staff/staff_profile.dart` | Taarifa binafsi | On each staff page (owner): phone, emergency contact, area, start date, NIDA masked with **Onyesha** (owner's PIN again; logged), consent, "Nani ameangalia?". Form with the consent checkbox; "Futa taarifa binafsi" after someone leaves. **Zaidi › Taarifa zangu** for staff: their own record and who accessed it. |
| `lib/core/pin_fields.dart` | PIN boxes | Max 4 digits, auto-advance, live ✓ Zinalingana / ✗ Hazilingani, easy-PIN warning; `askNewPin` for the owner's temporary PINs. |

### Invoice photo setup (once)
`flutter pub add image_picker`, then add the camera permission text to `ios/Runner/Info.plist` (see the v0.4 install notes).

## Next steps

1. Receive stock screen (supplier deliveries after the first import)
2. Server online with HTTPS, then TestFlight / APK for the pilot phones
