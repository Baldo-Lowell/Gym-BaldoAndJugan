# Jugan Gym (Flutter + Supabase + Xendit)

## 1. Create the Flutter project files
This folder has `lib/main.dart`, `pubspec.yaml` and `supabase/`. Generate the
Android/iOS folders around them once:

```bash
cd myapp
flutter create . --project-name myapp --org com.jugan
flutter pub get
```
(If it asks to overwrite `lib/main.dart`, keep yours.)

## 2. Supabase
1. Create a project at https://supabase.com
2. **SQL Editor** > paste all of `supabase/schema.sql` > Run.
3. **Authentication > Providers > Email**: enabled, keep **Confirm email** ON
   (this protects the admin email from being taken by someone else).
4. **Authentication > Users > Add user**: create the admin with the email in
   `kAdminEmails` (`jugan.johnmark.bandico@gmail.com`) and a strong password.
5. **Project Settings > API**: copy the Project URL and the `anon` key.

Run the app:
```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```
(or paste them as the defaults at the top of `lib/main.dart`).

## 3. Xendit (online payment: GCash, Maya, cards, banks)
1. Get your **Secret API key** (Xendit Dashboard > Settings > API Keys; use the
   test key first).
2. Deploy the two functions:
```bash
npm i -g supabase
supabase login
supabase link --project-ref <your-project-ref>

supabase secrets set XENDIT_SECRET_KEY=xnd_development_xxxxxxxx
supabase secrets set XENDIT_WEBHOOK_TOKEN=<verification token from Xendit webhooks page>

supabase functions deploy create-xendit-invoice
supabase functions deploy xendit-webhook --no-verify-jwt
```
3. Xendit Dashboard > Settings > Webhooks: set **Invoices paid** and
   **Invoices expired** to
   `https://<your-project-ref>.supabase.co/functions/v1/xendit-webhook`

How a purchase flows:
1. App calls `place_order` (stock checked + lowered, order saved, price from DB).
2. For online payment, the app calls `create-xendit-invoice` and opens the
   Xendit page.
3. Xendit calls `xendit-webhook` when paid / expired.
4. The webhook marks the order paid (or cancels it and restores stock), and the
   payment dialog in the app updates live through Realtime.

## Security notes
- The Xendit secret key and the Supabase `service_role` key stay on the server
  only. Never put them in the app.
- Orders can only be created through `place_order`, so customers cannot fake
  prices or skip stock checks.
- Admin rights come from the verified email in the login token
  (`public.is_admin()`), so keep **Confirm email** ON.
- A cancelled order that was paid anyway keeps `payment_status = paid`: refund
  it from the Xendit dashboard.
