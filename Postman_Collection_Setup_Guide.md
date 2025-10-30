# NeurXAxonChat API Postman Collection - Setup Guide

## Overview

This comprehensive Postman Collection includes all 49 endpoints from the NeurXAxonChat API, organized into logical folders by API phase. The collection includes authentication setup, pre-request scripts, and sample data for testing.

## Collection Structure

```
NeurXAxonChat API
├── Phase 1: Core Memory API (4 endpoints)
├── Phase 2: Conversation Management API (7 endpoints)
├── Phase 3: Artifact Management API (8 endpoints)
├── Phase 4: Settings & Projects API (10 endpoints)
├── Phase 5: Audio & Tool Execution API (7 endpoints)
├── Phase 6: Batch Operations & Import/Export (5 endpoints)
├── Phase 7: Advanced Features & Analytics (8 endpoints)
└── Utility & Test Endpoints (2 endpoints)
```

## Quick Start Guide

### Step 1: Import the Collection

1. **Download the collection file**: `NeurXAxonChat_API.postman_collection.json`
2. **Open Postman**
3. **Import the collection**:
   - Click "Import" button in the top left
   - Choose "Upload Files"
   - Select the JSON file
   - Click "Import"

### Step 2: Create Environment Variables

You need to create a Postman environment to store your authentication credentials:

1. **Create a new environment**:
   - Click the gear icon (⚙️) in the top right
   - Select "Add Environment"
   - Name it "NeurXAxonChat Dev" (or similar)

2. **Add the following variables**:

| Variable Name | Initial Value | Description |
|---------------|---------------|-------------|
| `baseUrl` | `https://us-central1-neurx-axon-chat.cloudfunctions.net` | API Base URL |
| `apiKey` | `YOUR_ADMIN_KEY` | Your admin API key |
| `firebaseIdToken` | `YOUR_FIREBASE_ID_TOKEN` | Firebase authentication token |
| `projectId` | `project-uuid` | Default project ID for testing |
| `conversationId` | `conv-uuid` | Default conversation ID |
| `memoryId` | `mem-uuid` | Default memory ID |
| `artifactId` | `art-uuid` | Default artifact ID |
| `targetMemoryId` | `target-mem-uuid` | Target memory for relationships |
| `messageId` | `msg-uuid` | Default message ID |
| `provider` | `anthropic` | API provider (anthropic, openai, etc.) |

3. **Set the environment** as active by selecting it from the environment dropdown

### Step 3: Authentication Setup

#### Firebase Authentication Token

To get a Firebase ID Token, you can use this JavaScript snippet:

```javascript
// Run this in your browser console after authenticating with Firebase
import { getAuth } from "firebase/auth";

const auth = getAuth();
const user = auth.currentUser;

if (user) {
    const idToken = await user.getIdToken();
    console.log('Firebase ID Token:', idToken);
    // Copy this token and paste it in your Postman environment
} else {
    console.log('No user is signed in');
}
```

Or use this cURL command to test authentication:

```bash
curl -X POST 'https://us-central1-neurx-axon-chat.cloudfunctions.net/api/auth/test' \
  -H 'Authorization: Bearer YOUR_FIREBASE_ID_TOKEN' \
  -H 'Content-Type: application/json'
```

#### API Key Setup

1. **Get your admin API key** from your NeurXAxonChat application settings
2. **Add it to the environment** as the `apiKey` variable

### Step 4: Testing the Collection

#### Basic Health Check

Start with the utility endpoints to verify connectivity:

1. **Select "Health Check"** from "Utility & Test Endpoints"
2. **Click "Send"**
3. **Verify response**: Should return a 200 status with service information

#### Test the Memory API

1. **Create a project first** (Phase 4):
   - Use "Create Project" with sample data
   - Copy the returned project ID
   - Update your `projectId` environment variable

2. **Test memory operations** (Phase 1):
   - Start with "Parse Memory Tags"
   - Then try "Create Memories (Batch)"
   - Finally test "Retrieve Memories"

#### Sequential Testing

For the best experience, test endpoints in this order:

1. **Phase 4**: Create a project and get settings
2. **Phase 1**: Create and retrieve memories
3. **Phase 2**: Create a conversation and add messages
4. **Phase 3**: Create an artifact
5. **Phase 5**: Test audio generation (if configured)
6. **Phase 6**: Test batch operations
7. **Phase 7**: View analytics and insights

## Features Included

### 🔧 Automated Scripts

- **Pre-request scripts**: Automatically add API key as query parameter
- **Response tests**: Validate HTTP status codes and JSON structure
- **Dynamic data**: Auto-update request bodies with test data

### 🔐 Authentication

- **Bearer token authentication** for Firebase ID tokens
- **Query parameter authentication** for API keys
- **Environment variable management**

### 📊 Sample Data

All endpoints include realistic sample data:
- Python learning examples
- Memory parsing with tags
- Code artifacts and documentation
- User settings and preferences

### 📝 Organized Structure

- **Phase-based organization** matching the API documentation
- **Clear endpoint descriptions** and use cases
- **Pagination parameters** for list endpoints
- **Query parameter examples** for filtering and sorting

## Environment Variable Management

### Getting Real IDs

As you test the API, you'll need to update environment variables with real IDs:

1. **Project ID**: From creating a project
2. **Conversation ID**: From creating a conversation
3. **Memory ID**: From creating memories
4. **Artifact ID**: From creating artifacts
5. **Message ID**: From adding messages

Use Postman's **Set an environment variable** feature in test scripts:

```javascript
// In test scripts, you can extract IDs like this:
const response = pm.response.json();
if (response.data && response.data.id) {
    pm.environment.set('projectId', response.data.id);
}
```

## Common Issues & Solutions

### Authentication Errors

**Problem**: 401 Unauthorized
**Solution**: 
- Verify your `firebaseIdToken` is valid and not expired
- Check that `apiKey` is correctly set
- Ensure both environment variables are properly configured

### Missing Project Context

**Problem**: 400 Bad Request for endpoints requiring projectId
**Solution**:
1. Create a project first using "Create Project"
2. Copy the returned ID to your `projectId` environment variable
3. Retry the failing request

### Memory Parsing Issues

**Problem**: Memory parse endpoints return empty results
**Solution**:
- Ensure your `responseText` includes proper `<memory>` XML tags
- Check that `confidence` values are between 0 and 1
- Verify `projectId` is valid

## Advanced Usage

### Batch Testing

Use Postman's **Collection Runner** to test multiple endpoints:

1. **Select the collection**
2. **Choose your environment**
3. **Select endpoints to test**
4. **Run the collection**

### Environment Switching

Create multiple environments for different stages:
- **Development**: For local testing
- **Staging**: For pre-production testing
- **Production**: For live API testing

### Variable Extraction

Use Postman's response handling to extract IDs:

```javascript
// Extract conversation ID from create response
const jsonData = pm.response.json();
if (jsonData.data && jsonData.data.id) {
    pm.environment.set('conversationId', jsonData.data.id);
    console.log('Set conversationId:', jsonData.data.id);
}
```

## Rate Limiting

Be aware of rate limits mentioned in the API documentation:

- **text_search**: 100 calls/day
- **code_execution**: 50 calls/day  
- **web_request**: 100 calls/day

Monitor usage via the "Get Tool Usage" endpoint.

## Export and Sharing

### Export Options

- **Collection JSON**: Share the collection file
- **Environment JSON**: Export environment variables
- **Documentation**: Postman auto-generates API documentation

### Team Sharing

1. **Share the collection file** via email or version control
2. **Export environment templates** with placeholder values
3. **Document authentication process** for team members

## Support

If you encounter issues:

1. **Check the API documentation** for endpoint details
2. **Review response status codes** and error messages
3. **Verify environment variables** are correctly set
4. **Test authentication** with simple endpoints first

---

## Collection Statistics

- **Total Endpoints**: 49
- **API Phases**: 7
- **Test Scripts**: Automated validation
- **Sample Data**: Comprehensive examples
- **Authentication**: Firebase + API Key

This collection provides complete coverage of the NeurXAxonChat API with professional-grade testing capabilities.
