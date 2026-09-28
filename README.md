# Ctrl + Ex + Delete

### Reflect. Rebuild. Reconnect.

**Ctrl + Ex + Delete (CED)** is an iOS breakup recovery application designed to help users take small steps toward rebuilding their everyday lives at their own pace.

The app combines psychology-informed activities, personal reflection, progress tracking, a virtual healing room, and an AI-powered healing companion named **Ced**.

This project is being developed as a **Fall 2026 Senior Capstone Project at the University of North Carolina at Greensboro (UNCG).**

---

## Project Overview

Ctrl + Ex + Delete provides users with a private and interactive space to reflect on their emotions, rebuild their independence, and reconnect with themselves after a breakup.

Instead of focusing only on how many days have passed, the app encourages users to complete meaningful activities, reflect on their experiences, and gradually track their progress.

There is **no sign-up or login system**. Users remain anonymous, with the backend using an anonymous installation ID rather than personal user accounts.

---

## Key Features

- **Daily Check-In**  
  Users answer short questions about how they are feeling to help determine their current emotional state.

- **Personalized Activities**  
  Ced recommends activities based on the user's check-in, mood, and progress.

- **Virtual Healing Room**  
  An interactive room serves as the main hub of the app, with objects that connect users to different features.

- **Memory Scrapbook**  
  Users can upload photos from completed activities and build a visual collection of their experiences and progress.

- **Talk It Through with Ced**  
  Users can write or speak with Ced when they feel the urge to contact their ex. Ced provides supportive reflection while helping users recognize patterns and triggers over time.

- **Progress & Insights**  
  Users can view completed activities and track their progress across different areas of recovery.

- **Moving Forward**  
  When users feel ready, they can reflect on their progress and complete their experience.

---

## Activity Categories

Activities are organized into four main categories:

- Emotional Regulation
- Detachment
- Identity Reconstruction
- Independence & Social Reconnection

---

## Prototype

Our high-fidelity prototype was created in Figma.

[**View the Ctrl + Ex + Delete High-Fidelity Prototype**](https://www.figma.com/make/duI7iQsbRaVqy7C29hRtjn/C-E-D-High-Fidelity-Prototype?code-node-id=0-6&p=f&t=UUIneb7l82DPCyL4-0&fullscreen=1)

---

## Technology Stack

- **iOS:** Swift, SwiftUI, Xcode
- **Backend:** Python, FastAPI
- **Database:** Neon PostgreSQL
- **Media Storage:** AWS S3
- **AI:** OpenAI API
- **Design & Development Tools:** Figma, GitHub, Postman

---

## System Architecture

The application follows a client-server architecture:

**SwiftUI iPhone App**  
↓  
**FastAPI / Python Backend**  
↓  
**Neon PostgreSQL + AWS S3 + OpenAI API**

### SwiftUI App

Handles the user-facing experience, including:

- Daily check-in
- Healing room
- Activities
- Scrapbook
- Ced interaction
- Progress and insights

### FastAPI Backend

Handles:

- API routes and application logic
- Check-in processing
- Activity recommendations
- Progress calculations
- Ced rules and AI communication
- Fact extraction

### Neon PostgreSQL

Stores structured application data, including:

- Check-ins
- Activities
- Progress
- Ced facts
- Scrapbook metadata

### AWS S3

Stores compressed scrapbook photos and provides secure image upload and retrieval.

### OpenAI API

Powers Ced's AI chat and voice functionality.

---

## Privacy & Safety

Ctrl + Ex + Delete does **not require users to create an account or sign in**.

Instead of traditional user accounts, the backend uses an **anonymous installation ID** to associate app data with an installation.

The OpenAI API key is kept on the backend and is never stored directly inside the iOS application.

Ced is intended to provide supportive reflection and general guidance. It is **not a replacement for professional mental health care and does not provide medical diagnoses or treatment.**

---

## Team & Responsibilities

### Ayusha Thapa — iOS Frontend / SwiftUI

Responsible for:

- Navigation
- Healing room
- Daily check-in UI
- Activity cards
- Scrapbook UI
- Insights
- Frontend API integration

### Sangye Tengkhar — AI Integration & Safety

Responsible for:

- OpenAI integration
- Ced prompts and personality
- Safe-response rules
- Fact extraction
- Crisis responses
- Voice prototype

### Alexa Chegue-Santos — Backend Logic & Recommendations

Responsible for:

- FastAPI routes
- Check-in processing
- Activity recommendation rules
- Progress scoring
- Insights logic

### Leonard Parra — Database & Media Storage

Responsible for:

- Neon PostgreSQL schema
- AWS S3 image storage
- Presigned upload/download URLs
- Scrapbook records
- Data retrieval and deletion

### Shared Team Responsibilities

All team members will contribute to:

- GitHub branches and version control
- Code reviews
- API and device testing
- Bug fixes
- Documentation
- Final demo preparation and rehearsal

---

## Development Schedule

### Week 1 — App Foundation + Check-In
Build the application's navigation and save check-in answers.

### Week 2 — Activity Recommendations
Implement activity suggestions, swiping, and activity completion.

### Week 3 — Healing Room
Build the healing room, Ced, and tappable objects linked to app features.

### Week 4 — Ced Chat + Insights
Connect the AI chat, safety support, and progress tracking.

### Week 5 — Feature Complete
Finish the scrapbook and connect all core features.

### Week 6 — Test, Polish + Present
Fix bugs, review AI responses, test the application, and rehearse the final demo.
