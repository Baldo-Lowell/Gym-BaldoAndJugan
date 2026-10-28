# Baldo And Jugan Gym - BMC Finals E-Commerce App

A Flutter mobile app with a protein/calorie calculator, workout log, rest timer, water tracker and a gym shop.
Backend: **Supabase** (login, database, realtime). Online payment: **Xendit** (GCash, Maya, cards, banks).

## Features
- User and Admin login (Supabase Auth)
- Gym shop: equipment, protein powder, energy drinks, cart, checkout
- Payment: Cash on delivery, or Online payment through Xendit
- Admin panel: add/edit/delete products, manage stock, view and complete/cancel orders
- Protein calculator, BMI/calories, workout log with 1RM, rest timer, water tracker

## Installation

### Option A: Install the APK (easiest)
1. Download the APK from the link: **PASTE APK LINK HERE**
2. Open it on an Android phone and allow "Install from unknown sources".
3. Log in with the accounts in the `.env` file.

### Option B: Run from source
Requirements: [Flutter SDK](https://docs.flutter.dev/get-started/install), VS Code or Android Studio.

```bash
git clone PASTE-YOUR-GITHUB-REPO-URL
cd myapp
flutter pub get
flutter run -d chrome \
  --dart-define=SUPABASE_URL=<SUPABASE_URL from .env> \
  --dart-define=SUPABASE_ANON_KEY=<SUPABASE_ANON_KEY from .env>
```

Build an APK:
```bash
flutter build apk --release --dart-define=SUPABASE_URL=<...> --dart-define=SUPABASE_ANON_KEY=<...>
```

## Supabase setup (only if using your own project)
1. Create a project at supabase.com.
2. SQL Editor: run `supabase/schema.sql`.
3. Authentication > Users: create the admin user (email in `kAdminEmails` in `lib/main.dart`).
4. Deploy the Edge Functions in `supabase/functions/` (`create-xendit-invoice`, `xendit-webhook`) and set the secrets `XENDIT_SECRET_KEY` and `XENDIT_WEBHOOK_TOKEN`.

## Test accounts
See the `.env` file (admin and user logins). Payments use Xendit **test mode**: no real money is charged.

## Tech stack
Flutter, Supabase (Postgres, Auth, Realtime, Edge Functions), Xendit.
