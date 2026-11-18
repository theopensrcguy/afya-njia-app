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
| `lib/features/orders/` | Agiza (v0.9) | **Zaidi › Agiza mzigo**: what runs out before the next delivery, grouped by supplier, each line saying why ("Itaisha baada ya siku 1!"), in that supplier's packs; 7/14/30 days; − / + per line. **Tuma** shows the message as the supplier will read it, the supplier's WhatsApp number (Weka/Badilisha, saved), then saves the order and opens WhatsApp (`wa.me`), or copies it for SMS. Needs `flutter pub add url_launcher`. |
| `lib/features/orders/` (v0.9.1), `lib/features/suppliers/` | Agiza + Wasambazaji | "Agiza kiasi cha kutosha kwa: Wiki 1 · Wiki 2 · Mwezi 1" (a labelled segmented choice). Each line says why it's there (Imeisha / Itaisha baada ya siku N / Chini ya kiwango). The **packaging is a button**: switch kadi → boksi (or a new one, e.g. katoni ya boksi 10) and the amount converts to about the same number of tablets. **+ Ongeza bidhaa** per supplier and **Agiza bidhaa nyingine yoyote** for anything else. "Maagizo N yanasubiriwa" lists sent orders, with "Funga: halitakuja". **Zaidi › Wasambazaji**: contact person, phone, WhatsApp, email, location, TIN, notes; tap to call / WhatsApp / email; deliveries, last delivery, open orders, TSh bought in 90 days. Pokea's "+ Mpya" supplier opens the same form. |
| `lib/features/bulk/bulk_entry_screen.dart` | Ingiza kwa wingi (v0.10, for a laptop) | One row per batch: Bidhaa (type → your products, this sheet's new ones, the catalogue "+ Mpya", or "Ongeza … kama bidhaa mpya") · Kifungashio (the product's units or a new one) · Idadi · Batch · EXP (06/2028) · Bei ya kununua · Bei ya kuuza. Tab moves on; Enter in the price cell = new row; Ctrl+N too. Rows show problems in red (blocks saving), warnings in amber (expiring soon, selling below cost), expired rows grey (left out). Two modes: **Hisa ya mwanzo** (no supplier) and **Mzigo wa msambazaji** (supplier, invoice number and total vs lines, "Jaza kutoka agizo"). **Bandika kutoka Excel** (Tab-separated: Bidhaa, Kifungashio, Ukubwa, Idadi, Batch, EXP, Bei; only exact names are matched). **Kagua** checks everything on the server without saving; **Hifadhi** saves through the same rules as Pokea mzigo. The app no longer uses `dart:io` (photo upload sends bytes), so it builds for the web. |
| `lib/features/auth/pin_screen.dart` (v0.11) | Kuingia | Depends on the device (the server decides): **personal** phone → "Karibu tena, Hamisi" + PIN, "Si wewe?" for anyone else; **shared** counter phone → round initials, most recent first, "Siko kwenye orodha"; **new** phone or browser → phone number + PIN, then the owner approves it. Phone-sized on wide screens; the PIN can be typed on a keyboard. Staff phone numbers: Wafanyakazi na ruhusa (list, ⋮ › Namba ya kuingia, and the owner's own at the top). Vifaa: a switch "Simu ya pamoja (kaunta)". |
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

## Web (browser) version

```bash
flutter create --platforms web .          # once: adds the web/ folder, keeps your code
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
flutter build web --dart-define=API_BASE_URL=https://api.example.co.tz/api   # for the server
```
The browser signs in with a PIN like a phone; the first time, the owner approves it (Vifaa). In `.env` on the server set `CORS_ALLOWED_ORIGINS` to the web app's address.

## Shared colours (v0.12)
`lib/core/brand.dart` now holds the same named colours as the web pages (`public/css/afya.css` in the backend): `primaryStrong` for green text on mint, `primarySoft`, `infoBlue` for "waiting for you", `warnSoft` and `dangerSoft` chip backgrounds, `momoPurple` for mobile money, `barNormal` / `barBest` for charts and `chartPalette`. `dangerRed` is now #C2412D, as on the web. The Flutter web build is set aside: the laptop uses the Laravel pages.

## Umesahau PIN? (v0.16)
`lib/features/auth/forgot_pin_screen.dart`, opened from every mode of the PIN screen: phone number → 6-digit code by SMS → new PIN twice. The server decides everything (same answer for unknown numbers, 5 tries, sign-out everywhere); back on the PIN screen the phone number is filled in.

## Kiswahili / English (v0.17)
- `lib/core/i18n.dart`: `tr('Hifadhi')` gives the text in the chosen language; `T('Hifadhi')` is a `Text` that does the same and can stay `const`. Placeholders like the server: `tr('Bidhaa :n', {'n': 3})`. English lives in `lib/core/i18n_en.dart` (Kiswahili is the key; a missing text shows in Kiswahili).
- **Switch:** *Kiswahili | English* at the top of the PIN screen, and *Zaidi → Lugha*. Signed in, the choice is saved on the person's account (`PATCH me/locale`) so the web follows; on sign-in, and on every home load, the app takes the person's saved language. Before sign-in the phone remembers the last one (secure storage).
- **Switching redraws everything:** open screens close and home is drawn fresh (the home screen is keyed on the language), so no screen keeps old text.
- Every request sends `X-Lang`, so server messages (wrong PIN, not enough stock…) arrive in the same language.
- Lists kept as `const` (months, bands, statuses) stay Kiswahili in code and are translated where they're shown, e.g. `Text(tr(label))`.

## Msaada (v0.18)
`lib/features/support/support_screen.dart`, from *Zaidi → Msaada*: the shop's support requests (owner: all; staff: their own), *Omba msaada* to write to Saola, and each request as a conversation with a reply box and *Funga ombi*. Saola's replies also arrive by SMS. Uses `GET/POST support`, `GET support/{id}`, `POST support/{id}/reply|close`. A paused pharmacy gets `403 pharmacy_inactive` with a message the app shows as-is.

## Split payments (v0.20)
The customer pays part by M-Pesa and part in cash. On the Kamilisha screen, **Gawanya malipo** (split payment) shows one row per way of paying.
- **The rows:** you type every part except the last. The last row is always *kinachobaki* (the rest), so the parts add up to the total even if the discount or a quantity changes afterwards. Up to three ways (cash, mobile, insurance); **Njia moja** (one way) goes back to a single method.
- **Where the rules live:** in `Cart` (`split`, `payments`, `splitProblem`), not in the screen. Kamilisha stays disabled while a part has no amount, the parts exceed the total, or a method is used twice.
- **What's sent:** `POST sales` gets `payments: [{method, amount}]` instead of `payment_method`. The server checks the parts add up exactly, so a wrong sum is refused and nothing leaves the shelf.
- **Receipt and lists:** the receipt dialog shows each part. The sales list and home card show "Simu 15,000 + Taslimu 5,000" (`paymentText()` in `core/format.dart`).

## Madeni and Matumizi (v0.21)
- **Kamilisha:** **Deni** (credit) is a way to pay for someone with `sell_on_credit`, alone or in a split. "Deni la nani?" (`features/credit/customer_picker.dart`) chooses or adds the customer. `Cart.splitProblem` refuses until the customer is chosen, approved and within their limit; the server checks it all again. The sale sends `customer_id`, and the WhatsApp receipt names who took the credit.
- **Zaidi → Madeni** (`features/credit/madeni_screen.dart`): owing / waiting / all. Tap a customer for their history, **Pokea malipo** (receive payment), and, with `manage_credit`, approve, set a limit or block. Home has a Madeni tile with the total, or "wanasubiri" (waiting) for whoever approves.
- **Zaidi → Matumizi** (`features/expenses/matumizi_screen.dart`): today / this month / last month, totals by type, **Ongeza matumizi** (type chips plus "Aina mpya", amount, cash/mobile/bank, date, note). Long-press an entry to void it.
- **Permissions:** `Perm.sellOnCredit`, `Perm.manageCredit`, `Perm.recordExpenses`.


## Credit approved per request (v0.21.1)
- **Sending a request:** at Kamilisha, a seller without `manage_credit` who uses Deni sends a **request**. The app says "Ombi la deni limetumwa" (credit request sent), the basket clears, and the medicine stays set aside on the server.
- **Maombi ya deni (credit requests)**, at the top of **Zaidi → Madeni**:
  - **Approvers** see every waiting request, with **Kubali** (approve) / **Kataa** (decline).
  - **Sellers** see their own: waiting (with **Ondoa ombi**, withdraw), approved ("mpe mteja dawa", give the medicine) or declined. Answers stay visible for 24 hours.
- **Home:** the Madeni tile shows "Maombi ya deni · n" to approvers.
- **Customers:** no longer need approval; blocking (and the optional limit) stays.

## Aina (categories) (v0.22)
- **Counter:** with the search empty, a row of chips: Zote (all), then each category that has products (Dawa, Vipodozi…), then Haijapangwa (not sorted). A chip lists that category (`GET products?category=`) and hides Haraka; typing searches everything.
- **Product page:** "Aina: …" opens a picker (`PATCH products/{id}` with `category_id`), for whoever may change prices.
- **New product in a delivery:** optional category chips. Left empty, the server guesses from the catalogue: medicines → Dawa, supplies → Vifaa tiba / Mama na mtoto.

## Agiza, Maagizo, new products (v0.23)
- **Agiza views:** Pendekezo / Tahadhari / Zote (`GET reorder?view=`), each with its count. Only suggested lines start with an amount; in Zote there is a name filter.
  - Choices made in one view stay when switching views; changing "Wiki 1 / Wiki 2 / Mwezi 1" starts again.
- **Bidhaa mpya from Agiza:** the product picker has "Bidhaa mpya (haipo dukani)", which uses the new-product form and `POST products/new` (with *create_products*); the product is then added to the order.
- **Order screen (`OrderSendScreen`):** each line has −/+ (0 leaves it out). **Hifadhi rasimu** saves a draft; `orderId` reopens a draft (PATCH) to finish and send it.
- **Maagizo (`orders/orders_screen.dart`):** from Agiza's app bar, the "yametumwa" banner, or the "Rasimu n hazijatumwa" banner.
  - Status chips and a supplier filter (including "Bila msambazaji").
  - Each order opens to its lines and message. Drafts: Maliza na tuma / Futa. Sent orders: Fungua WhatsApp tena / Ghairi. Any order: Nakili ujumbe.
- **Units (`stock/unit_picker.dart`):** standard units, then the shop's own (`GET units`), then "+ Kipimo kingine…". Used by the new-product form, "+ Nyingine" packaging in a delivery line, and Agiza.
- **Delivery:** a "Bidhaa mpya (haipo dukani)" button at the top of the product search. It asks for the generic name, searches the shop and the catalogue with it, and opens the form straight away when nothing matches.
  - The form says "Jina la dawa (generic)" and "Jina la kampuni / brand", and sends `generic_name` for products that aren't in the catalogue.

### v0.23.1: a supplier per line
- In Agiza each product shows "Kutoka: <supplier> ▾". Tapping it chooses another supplier (or none yet), and the list regroups (`_supplierOf`), so each supplier gets its own order. After a list is sent, only that list's products are cleared.

### v0.23.2: list menu
- Each Agiza list has a ⋮ menu with three items. "Agiza zote kutoka kwa…" sets one supplier for every product in it (each can still be changed under its name). "Chagua zote" keeps amounts already set and puts 1 on the rest. "Ondoa zote" sets every amount to 0.

### v0.23.4: continue a draft
- `ReorderScreen(draftId:)`: loads `GET purchase-orders/{id}` and shows a "Rasimu" card on top. Its lines use the same amount/packaging controls; its products are left out of the lists below.
  - The card has: "Ongeza bidhaa", "Badilisha" (supplier), **Hifadhi rasimu** (`PATCH`, stays), and **Angalia na tuma** (`OrderSendScreen(orderId:)`; once sent, the screen closes).
  - The lists' ⋮ menu gains "Weka zilizochaguliwa kwenye rasimu". `PopScope` asks before leaving unsaved changes.
- Maagizo → draft: **Endelea kuandaa** (continue) or **Iko tayari: tuma** (send as it is).

### v0.23.5: a supplier per product in a draft
- Draft lines carry `supplier_id`. The draft card shows one section per supplier, each with **Tuma kwa …** (`_sendDraftPart`): it saves the draft first, then opens `OrderSendScreen(draftPart: true)`.
  - That screen posts `purchase-orders/{id}/send` with only those lines, and hides "Hifadhi rasimu" there.
- "Kutoka:" on a draft product changes only that product. "Zote: …" in the card's header sets every product.
- Maagizo → draft: **Endelea kuhariri** (continue editing).

### v0.23.6: floating drafts button
- `ReorderScreen` has a `FloatingActionButton.extended` "Rasimu n" (`_showDrafts`: `GET purchase-orders?status=draft`, each with **Endelea kuhariri** → `ReorderScreen(draftId:)`). It flashes "Rasimu imehifadhiwa ✓" when a new draft was saved. The old drafts banner is gone, and the list has bottom padding so the button never covers it.

### v0.23.7: loader
- `core/loader.dart`:
  - **`AfyaLoader`**: the green "A" mark breathing inside a turning ring. It is used for every screen's first load (it replaces the plain `CircularProgressIndicator()`).
  - **`ActivityLayer`**: over every screen. It shows a thin bar while any request is out, and a centred loader "Inashughulikia…" when a save (POST/PATCH/PUT/DELETE) takes more than ~0.9 s.
- `ApiClient` counts requests in `apiActivity` / `apiSaving` (ValueNotifiers).

## Futa hisa with approval; units (v0.24)
- `features/stock/deletions_screen.dart`:
  - `askDeleteStock()` asks for the reason; an approver's deletion happens at once.
  - `DeletionsScreen`: approvers see "Idhinisha / Kataa", others "Ghairi ombi". It opens from the Hisa app bar icon, whose badge shows the count.
- Product page: a 🗑 on each batch, and "Futa bidhaa hii" / "Omba kufuta bidhaa hii" at the bottom. History shows "Imefutwa".
- `Perm.approveDeletions`; `confirmDialog()` in `core/dialogs.dart`.
- Units editor: names come from `pickUnitName`: standard units, the shop's own, then "+ Kipimo kingine…".

## Uhamisho wa hisa and Maduka yangu (v0.25)
- `features/transfers/transfers_screen.dart` (Zaidi → Uhamisho wa hisa):
  - this shop's code (copy), linked shops, link requests (Kubali / Kataa) and "Unganisha na duka jingine";
  - incoming transfers: **Pokea** shows where each line goes, **Kataa** sends it back;
  - waiting for approval: **Idhinisha, tuma** / Ghairi;
  - the history.
- `new_transfer_screen.dart`: the shop, the products (search), the amount and its unit side by side, and a note.
- `my_shops_screen.dart` (Zaidi → Maduka yangu, owners): the shops, **Fungua** switches (`Session.switchShop`: a new token, back to home), and "Ongeza duka langu jingine" (code + that shop's owner PIN).
- `Perm.transferStock`, `Perm.approveTransfers`. Product history shows the transfer movements.

## Wateja: a customer on any sale, and refill reminders (v0.26)
- **Checkout** (`features/sale/checkout_screen.dart`): "Weka mteja (si lazima)" when the sale has no credit. Picking someone who hasn't agreed opens "Muulize mteja"; only a yes puts the customer on the sale (`Cart.toRequest` sends `customer_id` on credit, or when `consent` is true). After the sale, the receipt dialog offers **Mkumbushe kurudia dawa** for a customer who agreed and has a phone.
- `features/customers/customer_consent.dart`: `askCustomerConsent`, `askRefillReminder`, `customerAgreed`, `phoneText`, `dayText`.
- `features/customers/customers_screen.dart` (Zaidi → Wateja, `Perm.viewCustomers`): who to remind today (WhatsApp opens on their chat with the message; "Nimemtumia" marks it; SMS when the server has a provider), reminders coming up, reminded and not back, and the customers who agreed; tapping one shows what they bought and "Ondoa ridhaa".
- `pickCustomer(..., forCredit: false)` shows phones instead of debts.
- The reminder message is written by the server and never names the medicine.

## One person, many shops (v0.27)
- `Staff.otherShops` (from `other_shops`). Zaidi → **Maduka yangu** shows for owners and for anyone whose number is in more than one shop.
- `my_shops_screen.dart` lists every shop on this number; a shop where they work is marked "mfanyakazi". **Fungua** switches. A worker's phone may first need that shop's owner to approve it: the server's message says so, with the code.
- "Ongeza duka langu jingine" (owners only) is now for a shop of theirs registered under another number. A shop Saola registers on their number appears by itself.
- Adding a worker whose number already uses Afya Njia: the app shows the server's message (they sign in with their own PIN, not the one typed).

## New shop requests and subscriptions (v0.28)
- `Staff.subscription` / `Staff.readOnly` (from `GET me`). The home screen shows the payment banner: to owners near the end and in grace, to everyone once the shop is read-only. Saving anything while read-only gets the server's message (`402 subscription_expired`).
- **Maduka yangu:** shows the subscription line of each shop (owners), **Omba duka jipya** (name, location, licence number, note), the owner's requests with their status (Ghairi while waiting), and "Ongeza duka langu jingine" for a shop registered under another number.

## Mobile money payments: "Lipia kwa simu" (v0.30)
- `features/billing/pay_dialog.dart` (`payForShop`):
  - choose the period (chips with amounts), the network (pre-selected from the number) and the paying number;
  - then "Angalia simu yako" while it checks the status every 3 s;
  - then success (paid until …) or failure (with the reason, and "Jaribu tena").
- `Staff.canPayOnline` (from `GET me`). The home banner's button is **Lipia sasa** when online payment is available. **Maduka yangu** has **Lipia** on each shop the owner can pay for.

## Phone numbers (v0.31)
- `core/phone_field.dart`: `PhoneField(controller: …)`.
  - A country code dropdown, then **digits only, up to that country's length** (Tanzania +255: 9), grouped `712 345 678`.
  - The leading 0 is dropped, a pasted `+254…` switches the country, and there is a hint when the number is too short or isn't a mobile number.
  - The controller holds the whole number for the server (`255712345678`).
  - `phoneProblem(full)` reports what's wrong; `parsePhone(raw)` splits a number into country and digits.
- Used on: sign in (`pin_screen.dart`, white card), Umesahau PIN, the customer consent and new-customer forms, suppliers (phone and WhatsApp), staff profiles (own and emergency phone), and the Lipia dialog.
- Shop location from the phone's GPS is not in the app yet (it needs the `geolocator` package and location permissions). For now owners set it on the web, and Saola sets it on its visit.

## v0.32 (web only)
The stock hub, Rafu, required-field marking, the empty-stock till and GPS region/place are web changes. The app is unchanged in v0.32.
- The server now refuses selling a product marked `needs_price` (`price_required`), and the app shows the server's message.
- The Rafu view, field highlighting and GPS in the app are still to come.

## v0.33 (web only)
Rafu (aisles), stock-taking and the Saola map are on the web. The app is unchanged, except:
- `Perm.countStock` (`count_stock`) has been added to `core/permissions.dart`; the owner's permission screen lists it from the server.
- The stock-take API (`/api/stock-counts…`) is ready for an app screen later.

## Hesabu ya hisa on the phone (v0.34)
- `features/stock/stock_count_screen.dart`. Open it from Hisa (the ✓ clipboard icon in the top bar) or from Zaidi → Hesabu ya hisa. You need `count_stock` or `adjust_stock`.
- **No open count:** an explanation and **Anza hesabu ya hisa**.
- **Counting:**
  - a progress card;
  - search, and the filters Zote / Bado / Zenye tofauti;
  - products grouped by aisle (category), with "d / n" per aisle;
  - each product has a small pack icon and a badge: dashed circle = not counted, ✓, −9, +2 (it pops when it changes).
- **Skani (scan):** scan a barcode to open that product (`products/barcode/{code}`).
- **Counting one product (bottom sheet):**
  - type packs plus loose units, or count batch by batch;
  - the system's number shows only after **Hifadhi** (save);
  - the result is ✓ (it moves on by itself) or Pungufu / Ziada with the TSh value;
  - **Hesabu tena** (count again) or **Inayofuata →** (next) walks to the next product not yet counted;
  - the phone gives a short vibration on each save.
- **Maliza na tuma** sends the count; **Historia** lists past counts.
- **Review:** the totals, the differences with value, and for approvers a checkbox per product, plus **Idhinisha marekebisho** (approve) / **Kataa** (reject, with a reason).
- English strings are added in `i18n_en.dart`. Checked with the Dart analyzer only.

## Sajili mteja (v0.36)
- The Wateja screen has a **Sajili mteja** button: name, `PhoneField`, an optional note, and a consent tick (required).
- When the number is already known (server answers 409 `customer_exists`), it offers to record consent on that customer.
- Checked with the Dart analyzer only.

## v0.37: sign-in fixed, Zaidi in groups, customers' reminders optional
- **Sign-in by phone number is now two steps:**
  1. the number, with an **Endelea** button. The iPhone number keyboard has no Done key; before this, the keyboard covered the PIN pad and there was no way forward, which looked like a freeze.
  2. the PIN: the number shows as a chip (tap it to change), then the keypad, plus a visible **Ingia** button (the 4th digit still signs in by itself).
  - The keys are a fixed size, and the page scrolls instead of squeezing on small screens or with the keyboard open.
  - The hint is an example number (712 345 678), not XXXXXXXXX.
- **LanguageSwitch** is drawn by hand: the language not chosen is outlined and readable on the green sign-in screen (it was white on white) and in the menu.
- **Zaidi** is a full page instead of a long sheet:
  - who is signed in, with Toka (sign out);
  - a search box;
  - four groups of tiles: Kila siku / Hisa na mizigo / Duka na watu / Mimi;
  - the language at the end;
  - 3 to 5 tiles per row depending on the screen width.
- **Customers:** reminders are a separate, optional tick when registering (Sajili mteja) and when agreeing at the till.
- Checked with the Dart analyzer only: no Flutter SDK can be downloaded in this environment, so it couldn't be run here. Test on the iPhone and iPad.

## v0.41: sign-in redesigned (app only)
Built from the approved design canvas "Afya Njia sign-in redesign" (4 boards). Only the look changed; the sign-in steps, device approval and Umesahau PIN work as before.
- **Phone:** a deep green top (logo, compact SW/EN switch, the title) and a white sheet below with the one thing to do.
  - **Step 1, Namba ya simu:** a "1 · Namba ya simu — 2 · PIN" step line, a large bordered number field, the example hint, then **Endelea** at the bottom, Umesahau PIN? and a footnote.
  - **Step 2, PIN:** a back button, "Weka PIN yako" and the number as a chip (**Badili** goes back). Four PIN boxes (the next one outlined in green, red after a wrong PIN), the error in a red banner, flat keys (Umesahau PIN? bottom left, delete bottom right), and **Ingia** (grey until 4 digits, "Inaingia…" with a spinner while signing in).
  - **Shared counter phone:** "Nani anaingia?" with a card per person (initials, name, role; scrolls sideways when there are many), "PIN ya {name}" in the sheet, and "Siko kwenye orodha: ingia kwa namba".
  - **Personal phone:** "Karibu tena, {name}" and "Si wewe? Ingia kwa namba".
  - Device approval (the 6-digit number) and the "couldn't load" message use the same sheet.
- **iPad / computer (900px wide or more):** the brand on a green panel on the left (three lines on what the app does), the form in a centred 380px column on the right. The computer keyboard types the PIN.
- `LanguageSwitch(compact: true)` shows SW / EN instead of the full names.
- Checked with the Dart analyzer only: no Flutter SDK can be downloaded in this environment, so it couldn't be run here. Test on the iPhone and the iPad (phone step, PIN step, a wrong PIN, a shared phone with 4+ people, and the iPad side by side).

### v0.41.1: "Siko kwenye orodha" always in view
- On the shared counter phone, **"Siko kwenye orodha? Ingia kwa namba"** now sits in the green header, right under the people cards. Someone whose name isn't there looks exactly there. Before, it was at the bottom under the keypad, below the fold on an iPhone. On a personal phone, **"Si wewe? Ingia kwa namba"** sits under "Karibu tena, {name}". iPad: the same, under the names.
- **Key height follows the screen:** 60 on tall screens, 54 on most iPhones, 48 on small ones. The PIN boxes follow too. So the shared screen (names, boxes, keypad, Ingia) fits without scrolling; scrolling stays only as a fallback.
- The PIN hint line is shown only on the phone-number route, to save room on the shared screen.
- Lint fixes in `customers_screen.dart`: `this.context` after the await; braces on a multi-line `if`.
