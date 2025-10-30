# Google Jules API - Complete Methods Documentation

Google's Jules API enables programmatic access to Jules, an AI-powered asynchronous coding agent, allowing developers to automate software development tasks, integrate with existing workflows, and embed Jules into tools like Slack, Linear, and GitHub [1][2].

## Authentication

All API requests require authentication using an API key generated from the Jules web app Settings page [1]. The API key must be passed in the `X-Goog-Api-Key` header for every request [1].

**Base URL:** `https://jules.googleapis.com` [3]

## Core Concepts

The Jules API is built around three primary resources [1]:

- **Source:** An input source for the agent, such as a GitHub repository that must be connected through the Jules web app before API use [1]
- **Session:** A continuous unit of work within a specific context, initiated with a prompt and source [1]
- **Activity:** Individual units of work within a session, including actions from both the user and agent [1]

## API Methods Reference

### v1alpha.sessions

#### sessions.create

Creates a new session to assign a task to Jules [3][4].

- **HTTP Method:** `POST`
- **Endpoint:** `/v1alpha/sessions`
- **Request Body:** Session object containing:
  - `prompt` - The task description
  - `sourceContext` - Object with source reference and GitHub context
  - `title` - Session title
  - `requirePlanApproval` - Boolean (optional, defaults to false for API sessions)
- **Response:** Newly created Session object with `name`, `id`, `title`, and `sourceContext` [1]

**Example:**
```bash
curl 'https://jules.googleapis.com/v1alpha/sessions' \
  -X POST \
  -H "Content-Type: application/json" \
  -H 'X-Goog-Api-Key: YOUR_API_KEY' \
  -d '{
    "prompt": "Create a boba app!",
    "sourceContext": {
      "source": "sources/github/owner/repo",
      "githubRepoContext": {
        "startingBranch": "main"
      }
    },
    "title": "Boba App"
  }'
```

#### sessions.get

Retrieves a single session by its resource name [3][5].

- **HTTP Method:** `GET`
- **Endpoint:** `/v1alpha/{name=sessions/*}`
- **Path Parameters:**
  - `name` (required) - Resource name format: `sessions/{session}` [5]
- **Request Body:** Empty [5]
- **Response:** Session object [5]

**Example:**
```bash
curl 'https://jules.googleapis.com/v1alpha/sessions/SESSION_ID' \
  -H 'X-Goog-Api-Key: YOUR_API_KEY'
```

#### sessions.list

Lists all sessions with pagination support [3][6].

- **HTTP Method:** `GET`
- **Endpoint:** `/v1alpha/sessions`
- **Query Parameters:**
  - `pageSize` (optional) - Number of sessions to return (1-100, defaults to 30) [6]
  - `pageToken` (optional) - Token from previous response for pagination [6]
- **Request Body:** Empty [6]
- **Response:** Object containing `sessions[]` array and `nextPageToken` [6]

**Example:**
```bash
curl 'https://jules.googleapis.com/v1alpha/sessions?pageSize=5' \
  -H 'X-Goog-Api-Key: YOUR_API_KEY'
```

#### sessions.approvePlan

Approves the execution plan in a session that requires explicit plan approval [3][7].

- **HTTP Method:** `POST`
- **Endpoint:** `/v1alpha/{session=sessions/*}:approvePlan`
- **Path Parameters:**
  - `session` (required) - Resource name format: `sessions/{session}` [7]
- **Request Body:** Empty [7]
- **Response:** Empty on success [7]

**Example:**
```bash
curl 'https://jules.googleapis.com/v1alpha/sessions/SESSION_ID:approvePlan' \
  -X POST \
  -H "Content-Type: application/json" \
  -H 'X-Goog-Api-Key: YOUR_API_KEY'
```

#### sessions.sendMessage

Sends a message from the user to an active session, allowing follow-up instructions or clarifications [3][1].

- **HTTP Method:** `POST`
- **Endpoint:** `/v1alpha/{session=sessions/*}:sendMessage`
- **Path Parameters:**
  - `session` (required) - Resource name format: `sessions/{session}`
- **Request Body:** Object containing:
  - `prompt` - The message text to send to Jules [1]
- **Response:** Updated session state

**Example:**
```bash
curl 'https://jules.googleapis.com/v1alpha/sessions/SESSION_ID:sendMessage' \
  -X POST \
  -H "Content-Type: application/json" \
  -H 'X-Goog-Api-Key: YOUR_API_KEY' \
  -d '{
    "prompt": "Can you make the app corgi themed?"
  }'
```

### v1alpha.sessions.activities

#### sessions.activities.get

Retrieves a single activity from a session [3].

- **HTTP Method:** `GET`
- **Endpoint:** `/v1alpha/{name=sessions/*/activities/*}`
- **Path Parameters:**
  - `name` (required) - Resource name format: `sessions/{session}/activities/{activity}`
- **Request Body:** Empty
- **Response:** Activity object

#### sessions.activities.list

Lists all activities within a specific session, showing the progression of work [3][8].

- **HTTP Method:** `GET`
- **Endpoint:** `/v1alpha/{parent=sessions/*}/activities`
- **Path Parameters:**
  - `parent` (required) - Session resource name
- **Query Parameters:**
  - `pageSize` (optional) - Number of activities to return (1-100, defaults to 50) [8]
  - `pageToken` (optional) - Token for pagination
- **Request Body:** Empty
- **Response:** Object containing activities array and pagination token

**Example:**
```bash
curl 'https://jules.googleapis.com/v1alpha/sessions/SESSION_ID/activities?pageSize=30' \
  -H 'X-Goog-Api-Key: YOUR_API_KEY'
```

### v1alpha.sources

#### sources.get

Retrieves details about a single source (GitHub repository) [3].

- **HTTP Method:** `GET`
- **Endpoint:** `/v1alpha/{name=sources/**}`
- **Path Parameters:**
  - `name` (required) - Source resource name format: `sources/{source}`
- **Request Body:** Empty
- **Response:** Source object

#### sources.list

Lists all sources connected to Jules, including GitHub repositories [3][1].

- **HTTP Method:** `GET`
- **Endpoint:** `/v1alpha/sources`
- **Query Parameters:**
  - `pageSize` (optional) - Number of sources to return
  - `pageToken` (optional) - Token for pagination
- **Request Body:** Empty
- **Response:** Object containing `sources[]` array with `name`, `id`, and `githubRepo` details, plus `nextPageToken` [1]

**Example:**
```bash
curl 'https://jules.googleapis.com/v1alpha/sources' \
  -H 'X-Goog-Api-Key: YOUR_API_KEY'
```

## Use Cases

The Jules API enables powerful automation workflows [1][9]:

- Creating custom integrations with Slack for ChatOps workflows to assign coding tasks directly from chat
- Automating bug fixing and feature implementation by connecting to project management tools like Linear or Jira
- Integrating Jules into CI/CD pipelines in services like GitHub Actions
- Building custom developer tools and IDE plugins
- Triggering automated code reviews and testing workflows

## API Version

The current API version is `v1alpha`, indicating it's in early release with potential future changes [3][2].

Sources
[1] Jules API https://developers.google.com/jules/api
[2] Level Up Your Dev Game: The Jules API is Here! https://developers.googleblog.com/en/level-up-your-dev-game-the-jules-api-is-here/
[3] Jules API https://developers.google.com/jules/api/reference/rest
[4] Method: sessions.create | Jules API https://developers.google.com/jules/api/reference/rest/v1alpha/sessions/create
[5] Method: sessions.get | Jules API https://developers.google.com/jules/api/reference/rest/v1alpha/sessions/get
[6] Method: sessions.list | Jules API https://developers.google.com/jules/api/reference/rest/v1alpha/sessions/list
[7] Method: sessions.approvePlan | Jules API https://developers.google.com/jules/api/reference/rest/v1alpha/sessions/approvePlan
[8] Method: sessions.activities.list | Jules API https://developers.google.com/jules/api/reference/rest/v1alpha/sessions.activities/list
[9] Changelog https://jules.google/docs/changelog/
[10] Jules - An Asynchronous Coding Agent https://jules.google
[11] New ways to build with Jules, our AI coding agent https://blog.google/technology/google-labs/jules-tools-jules-api/
[12] Google's Jules enters developers' toolchains as AI coding ... https://techcrunch.com/2025/10/02/googles-jules-enters-developers-toolchains-as-ai-coding-agent-competition-heats-up/
[13] Jules CLI Hands-On: Integrating Google AI Assistant into ... https://skywork.ai/blog/jules-cli-hands-on-integrating-google-ai-assistant-into-terminal-and-ci/
[14] How to Use Google Jules: A Beginners' Guide https://apidog.com/blog/google-jules/
[15] Getting started https://jules.google/docs
[16] Jules API — Jules 0.3.0 documentation - Read the Docs https://jules.readthedocs.io/en/latest/api.html
[17] Meet Jules Tools: A Command Line Companion ... https://developers.googleblog.com/en/meet-jules-tools-a-command-line-companion-for-googles-async-coding-agent/
[18] Welcome to Jules! — Jules 0.3.0 documentation https://jules.readthedocs.io
[19] Level Up Your Dev Game: The Jules API is Here! https://developers.googleblog.com/es/level-up-your-dev-game-the-jules-api-is-here
[20] Class SessionCreateParams.Builder https://stripe.dev/stripe-java/com/stripe/param/checkout/SessionCreateParams.Builder.html
[21] Parameters | Conversational Agents https://cloud.google.com/dialogflow/cx/docs/concept/parameter
[22] Custom session#create parameters - ruby on rails https://stackoverflow.com/questions/38047902/custom-sessioncreate-parameters
[23] Dynamically generating param values for an API and ... https://community.gatling.io/t/dynamically-generating-param-values-for-an-api-and-setting-it-using-session/7041
[24] java - How do I get a list of all HttpSession objects in a web ... https://stackoverflow.com/questions/3771103/how-do-i-get-a-list-of-all-httpsession-objects-in-a-web-application
[25] Running Tasks with Jules https://jules.google/docs/running-tasks/
[26] Create Or Update Session - Julep https://docs.julep.ai/api-reference/sessions/create-or-update-session
[27] How to list all methods of a class (not Extended and ... https://stackoverflow.com/questions/34357605/how-to-list-all-methods-of-a-class-not-extended-and-included-methods
[28] Google's coding agent Jules now works in the command line https://sdtimes.com/softwaredev/googles-coding-agent-jules-now-works-in-the-command-line/
[29] Manage sessions using direct API calls | Generative AI on ... https://cloud.google.com/vertex-ai/generative-ai/docs/agent-engine/sessions/manage-sessions-api
[30] SessionInfo | Conversational Agents https://cloud.google.com/dialogflow/cx/docs/reference/rest/v3/SessionInfo
[31] Get Request and Session Parameters and Attributes from ... https://stackoverflow.com/questions/550448/get-request-and-session-parameters-and-attributes-from-jsf-pages
[32] Jules Tools Reference https://jules.google/docs/cli/reference
[33] a major leap in AI-powered coding innovation! https://www.youtube.com/watch?v=hEV0JXQSu_w
[34] Retrieve the session value and pass as required parameter ... https://stackoverflow.com/questions/47701392/retrieve-the-session-value-and-pass-as-required-parameter-of-api-ajax
[35] Session Based Messaging API https://docs.gigaspaces.com/16.2.1/dev-java/session-based-messaging-api.html
[36] Google Jules MCP https://glama.ai/mcp/servers/@mberjans/google-jules-mcp/blob/8c79044680d9102efb8327b9300ae3f4c10973c8/src/index.ts
