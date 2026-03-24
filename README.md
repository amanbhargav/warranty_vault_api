# Warranty Vault API

A robust backend API built with Ruby on Rails for managing product warranties and invoices. The system allows users to upload invoices, automatically extract product details, track warranties, and receive timely reminders.

---

## 🚀 Features

* 🔐 JWT Authentication (Email + Google OAuth)
* 📄 Invoice Upload & OCR Processing
* 🤖 AI + Rule-Based Data Extraction
* 🧾 Multi-Warranty Support (Product + Components)
* ⏰ Warranty Expiry Tracking & Reminders
* 🔔 In-App Notifications (ActionCable)
* 📬 Email Notifications (Verification + Reminders)
* 📦 Background Jobs (Sidekiq)

---

## 🏗 Tech Stack

* Ruby on Rails (API mode)
* PostgreSQL
* Sidekiq + Redis
* ActionCable (WebSockets)
* OmniAuth (Google OAuth)
* ActiveStorage (local / S3-ready)

---

## ⚙️ Setup Instructions

### 1. Clone Repository

```bash
git clone <repo-url>
cd warranty-vault-api
```

### 2. Install Dependencies

```bash
bundle install
```

### 3. Setup Database

```bash
rails db:create db:migrate db:seed
```

### 4. Configure Environment

Create `.env` file:

```
DATABASE_URL=postgresql://localhost:5432/warranty_vault_development
JWT_SECRET_KEY=your_secret_key
FRONTEND_URL=http://localhost:3000

GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
```

### 5. Start Services

```bash
rails server
bundle exec sidekiq
redis-server
```

---

## 🔄 API Flow

1. User uploads invoice
2. OCR extracts text
3. AI parses structured data
4. Warranty details saved
5. Expiry calculated
6. Notification scheduled

---

## 📌 Key Endpoints

* POST `/api/v1/auth/signup`
* POST `/api/v1/auth/login`
* GET `/auth/google`
* POST `/api/v1/invoices/upload`
* GET `/api/v1/notifications`

---

## 🔐 Authentication

Uses JWT-based authentication.

Include token:

```
Authorization: Bearer <token>
```

---

## 🧠 System Highlights

* Hybrid AI + Rule-based parsing
* Multi-warranty support (e.g. product + compressor)
* Scalable job system for reminders
* Clean modular service architecture

---

## 📦 Future Improvements

* AWS S3 integration
* Push notifications
* Advanced analytics dashboard
* Multi-device sync

---

## 🤝 Contributing

Feel free to fork and contribute improvements.

---

## 📄 License

MIT License
