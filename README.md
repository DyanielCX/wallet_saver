## 🤖 Vibe-coded project

This project was **vibe-coded** — built conversationally with an AI coding agent rather than hand-written line by line.

- **Built with:** [Claude Code](https://claude.com/claude-code), Anthropic's agentic coding CLI
- **Model:** Claude Opus 4.8 (`claude-opus-4-8`)
- **How:** Architecture, Flutter/Dart implementation, and this documentation were generated through an iterative chat-driven workflow.

---

# Wallet Saver

**Wallet Saver** is a lightweight, offline-first personal finance app for tracking day-to-day income and expenses. Everything lives on-device — no account, no cloud sync, no network dependency. Log transactions in seconds, watch your budgets, and review where the money goes.

## Features

- **Transactions** — record income and expenses against categories, with notes, dates, and a built-in calculator keypad for quick amount entry.
- **Categories** — ships with sensible defaults (Food, Transport, Groceries, Salary, …) and supports your own custom categories with emoji icons.
- **Budgets** — set monthly or overall spending limits per category and track usage against them.
- **Recurring transactions** — define templates (e.g. rent, salary, subscriptions) that auto-generate transactions when they come due, with catch-up on app launch.
- **Reports** — visual breakdowns of spending and income over time, powered by charts.
- **CSV import/export** — back up or move your data via the device file picker; flexible column mapping on import.
- **Local notifications** — reminders surfaced through the OS notification system.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Dart |
| Framework | Flutter (cross-platform: Android, iOS, web, desktop) |
| Local database | SQLite via [`sqflite`](https://pub.dev/packages/sqflite) |
| Charts | [`fl_chart`](https://pub.dev/packages/fl_chart) |
| Notifications | [`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications) |
| CSV | [`csv`](https://pub.dev/packages/csv) + [`file_picker`](https://pub.dev/packages/file_picker) |
| Formatting / i18n | [`intl`](https://pub.dev/packages/intl) |
| Paths | [`path`](https://pub.dev/packages/path) |

## Architecture

Wallet Saver follows a pragmatic, layered structure under `lib/`. The UI talks to a thin service/data layer; a single `DatabaseHelper` is the only access point to SQLite.

```
lib/
├── main.dart                  App entry: init notifications, run due recurring
│                              transactions, launch the app
├── theme.dart                 App-wide Material theme
│
├── models/                    Plain data classes (toMap / fromMap)
│   ├── app_transaction.dart   A single income/expense entry
│   ├── category.dart          Income/expense category (+ emoji icon)
│   ├── budget.dart            Per-category spending limit (monthly/overall)
│   └── recurring_template.dart Schedule for auto-generated transactions
│
├── db/
│   └── database_helper.dart   Singleton SQLite access; schema, migrations,
│                              and all CRUD/queries
│
├── services/                  Business logic & integrations
│   ├── csv_service.dart       CSV import/export via the file picker
│   ├── notification_service.dart  Local notification scheduling
│   ├── recurring_service.dart Materialises due recurring templates
│   └── sync_service.dart      (Stub) credential/sync helper
│
├── screens/                   Full-page UI, one per app section
│   ├── main_scaffold.dart     Bottom-nav shell (4 tabs)
│   ├── home_screen.dart       Transactions list + summary (Transactions tab)
│   ├── reports_screen.dart    Charts & breakdowns (Reports tab)
│   ├── budgets_screen.dart    Budget setup & tracking (Budgets tab)
│   ├── settings_screen.dart   Import/export & management (Settings tab)
│   ├── categories_screen.dart Manage categories
│   ├── add_transaction_screen.dart   Create/edit a transaction
│   ├── recurring_screen.dart  List recurring templates
│   └── recurring_edit_screen.dart    Create/edit a recurring template
│
├── widgets/
│   └── calculator_keypad.dart Reusable numeric keypad for amount entry
│
└── utils/
    ├── calculator.dart        Expression evaluation for the keypad
    └── format.dart            Currency / date formatting helpers
```

**Navigation.** A single `MainScaffold` hosts a `NavigationBar` with four tabs — **Transactions**, **Reports**, **Budgets**, **Settings** — each backed by its own screen.

**Data flow.** Screens call into `services/` (or directly into `DatabaseHelper` for reads). `DatabaseHelper` is a singleton that owns the SQLite connection, defines the schema (`categories`, `transactions`, `budgets`, `recurring_templates`), handles versioned migrations, and seeds default categories on first run. Models are simple immutable classes that serialize to/from `Map` for storage.

**Startup.** `main()` initializes the notification plugin and runs `RecurringService.processDue()` so any recurring transactions that fell due while the app was closed are created before the first frame.

## Getting Started

```bash
flutter pub get
flutter run
```

Requires the Flutter SDK (stable channel). The app runs on Android, iOS, web, and desktop targets, though it's designed primarily for mobile.
