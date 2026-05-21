
# README_EXPLANATION.md

---

## Most Important and Useful Parts of the Code

### 1. **Main Screen and Navigation**
- **`lib/main.dart`**: App entry point. Initializes key services (notifications, storage, location) and global state.
- **`lib/app/routes.dart`**: Defines the main app routes (create alarm, alarm trigger, settings, etc.).
- **`lib/screens/traveller/traveller_shell.dart`**: Controls tab navigation (map, guide, alarms) and the bottom navigation bar. Allows switching between main features.

### 2. **Smart Guide and Plan Generation**
- **`lib/screens/traveller/traveller_guide_screen.dart`**: Central screen to interact with the assistant. Allows:
  - Chatting with the guide (conversational mode)
  - Generating a personalized plan (with stops, duration, budget)
  - Refining the plan with "quick actions" (cheaper, less walking, etc.)
  - Viewing the details of the generated plan
- **`lib/services/gemini_guide_service.dart`**: Service that connects the frontend with the backend to request plan generation/refinement using Gemini. Manages HTTP calls and response parsing.
- **`lib/models/mock_plan_model.dart`**: Defines the structure of a plan (stops, descriptions, coordinates, etc.) and its validation.

### 3. **Node.js Backend (Gemini Proxy)**
- **`backend/src/server.js`**: Express server exposing endpoints for:
  - `/api/guide/initial-plan`: Generate an initial plan
  - `/api/guide/refine-plan`: Refine an existing plan
  - `/health`: Backend health check
  - Includes logic to build prompts, validate payloads, and handle errors.
- **Custom prompts**: The backend builds specific prompts for Gemini depending on the request type (chat, generation, refinement), ensuring useful responses in the expected format.

### 4. **Visualization and User Experience**
- **`lib/widgets/guide/plan_card.dart`**: Widget that visually displays the generated plan, with numbered stops and details.
- **`lib/screens/shared/mode_selection_screen.dart`**: Screen to choose the app usage mode.
- **`web/index.html`**: Configuration for the web version, including Google Maps integration.

### 5. **State Management and Services**
- **`lib/providers/app_state_provider.dart`**: Global state provider to manage the user, current plan, chat messages, etc.
- **Services**: Local notifications, persistent storage, location, etc.

---

## What to Show in the Meeting?
1. **Main user flow**: From opening the app, choosing a mode, interacting with the guide, generating/refining a plan, and viewing it.
2. **Conversational interface**: How the user can chat and request changes to the plan.
3. **Automatic plan generation**: Explain how the AI (Gemini) generates personalized plans and how prompts are integrated.
4. **Modular architecture**: Clear separation between frontend (Flutter), backend (Node.js), and services.
5. **Plan visualization**: Show the plan widget and how stops are presented.
6. **Extensibility**: How more modes, services, or integrations can be easily added.

---

## Tips for the Demo
- Show the interaction with the guide and the real-time plan generation.
- Explain the plan data structure and how it is validated.
- Show the backend and how prompts for the AI are built.
- Highlight the user experience and intuitive navigation.
