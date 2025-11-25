# WhatsApp Integration

This document explains how WhatsApp messaging is integrated into the application, similar to the existing SMS functionality.

## Overview

WhatsApp integration allows users to:
- Receive WhatsApp messages in their inbox (grouped by phone number, similar to SMS)
- Send WhatsApp messages directly from the app
- Use the same message thread/conversation interface as SMS and email

## Architecture

The WhatsApp integration follows the same pattern as SMS:

### Core Components

1. **WhatsAppSyncService** (`lib/services/whatsapp/whatsapp_sync_service.dart`)
   - Manages credentials and settings
   - Stores access token, phone number ID, and account associations securely

2. **WhatsAppMessageConverter** (`lib/services/whatsapp/whatsapp_message_converter.dart`)
   - Converts WhatsApp Business API events to `MessageIndex` format
   - Uses phone number as thread ID (format: `whatsapp_thread_{normalized_number}`)
   - Message ID format: `whatsapp_{uuid}` or uses WhatsApp message ID

3. **WhatsAppSyncManager** (`lib/services/whatsapp/whatsapp_sync_manager.dart`)
   - Manages receiving WhatsApp messages
   - Currently supports webhook-based receiving (requires backend endpoint)
   - Note: WhatsApp Business API doesn't support polling like SMS/Pushbullet

4. **WhatsAppSender** (`lib/services/whatsapp/whatsapp_sender.dart`)
   - Sends WhatsApp messages via WhatsApp Business API
   - Handles phone number sanitization (E.164 format)

5. **WhatsAppApiService** (`lib/services/whatsapp/whatsapp_api_service.dart`)
   - Low-level API wrapper for WhatsApp Business API
   - Handles sending messages and parsing webhook events

## Setup Requirements

### 1. WhatsApp Business API Account

You need:
- A Meta Business account
- WhatsApp Business API access (via Meta Cloud API or Business Platform)
- A verified phone number for your WhatsApp Business account

### 2. Required Credentials

- **Access Token**: WhatsApp Business API access token
- **Phone Number ID**: Your WhatsApp Business phone number ID (found in Meta Business Manager)
- **Phone Number** (optional): Your WhatsApp phone number in E.164 format (e.g., +1234567890)

### 3. Configuration

1. Open Settings → Accounts
2. Scroll to "WhatsApp Sync" section
3. Enter your credentials:
   - Access Token
   - Phone Number ID
   - Your WhatsApp Number (optional)
4. Click "Save Credentials"
5. Toggle "WhatsApp Sync" to enable

## How It Works

### Receiving Messages

**Current Implementation:**
- Uses webhook-based receiving
- You need to set up a webhook endpoint that calls `WhatsAppSyncManager.processWebhookEvent()`
- The webhook should be configured in Meta Business Manager to point to your server

**Future Enhancement:**
- Could implement a polling mechanism if Meta provides such an API
- Could use a third-party service similar to Pushbullet for SMS

### Sending Messages

1. User replies to a WhatsApp message in the app
2. The app extracts the phone number from the message thread
3. `WhatsAppSender` sends the message via WhatsApp Business API
4. The message appears in the conversation view immediately

### Message Storage

- WhatsApp messages are stored in the same `messages` table as email and SMS
- Thread ID format: `whatsapp_thread_{normalized_phone_number}`
- Messages are grouped by phone number (same as SMS)
- Folder: `INBOX` for received messages, `SENT` for sent messages

## Differences from SMS

| Feature | SMS (Pushbullet) | WhatsApp (Business API) |
|---------|------------------|------------------------|
| Receiving | WebSocket real-time | Webhook (requires server) |
| Sending | Direct API call | Direct API call |
| Phone Format | Any format | E.164 format required |
| Message Limit | None | Rate limits apply |
| Media Support | Text only | Text, images, documents |
| Cost | Pushbullet subscription | Per-message pricing |

## Webhook Setup (Required)

To receive WhatsApp messages, you need to:

1. **Set up a webhook endpoint** in your backend:
   ```dart
   // Example webhook endpoint
   POST /webhook/whatsapp
   {
     "entry": [...]
   }
   
   // Process the webhook
   final whatsappManager = WhatsAppSyncManager();
   await whatsappManager.processWebhookEvent(webhookData);
   ```

2. **Configure webhook in Meta Business Manager**:
   - Go to Meta Business Manager
   - Navigate to WhatsApp → API Setup
   - Set webhook URL: `https://your-server.com/webhook/whatsapp`
   - Set verify token (optional, but recommended)
   - Subscribe to `messages` event

3. **Verify webhook**:
   - Meta will send a GET request to verify your webhook
   - Use `WhatsAppApiService.verifyWebhookChallenge()` to verify

## Integration Points

### UI Components

- **Email Viewer**: Shows WhatsApp messages in conversation mode (auto-enabled)
- **Home Screen**: Receives new WhatsApp messages via callback
- **Settings**: WhatsApp sync configuration widget
- **Message List**: WhatsApp messages show with WhatsApp icon (similar to SMS)

### Message Detection

- Use `WhatsAppMessageConverter.isWhatsAppMessage(message)` to check if a message is WhatsApp
- Use `WhatsAppMessageConverter.extractPhoneNumber(message)` to get phone number

## Limitations

1. **Webhook Required**: Unlike SMS (which uses Pushbullet WebSocket), WhatsApp requires a webhook endpoint
2. **Rate Limits**: WhatsApp Business API has rate limits
3. **Media Messages**: Currently only text messages are supported (can be extended)
4. **Template Messages**: For certain use cases, you may need to use WhatsApp message templates

## Future Enhancements

- [ ] Media message support (images, documents)
- [ ] Webhook endpoint implementation (backend)
- [ ] Polling alternative (if available)
- [ ] Template message support
- [ ] Group chat support
- [ ] Read receipts and delivery status

## Testing

To test WhatsApp integration:

1. Set up test credentials in settings
2. Send a test message from another WhatsApp account to your business number
3. Verify the message appears in the inbox
4. Reply to the message
5. Verify the reply is sent via WhatsApp Business API

## Troubleshooting

**Messages not appearing:**
- Check webhook is configured correctly
- Verify webhook endpoint is accessible from Meta's servers
- Check access token is valid
- Verify phone number ID is correct

**Cannot send messages:**
- Verify access token has send message permissions
- Check phone number format (must be E.164)
- Verify recipient number is registered on WhatsApp
- Check rate limits haven't been exceeded

**Credentials not saving:**
- Ensure secure storage permissions are granted
- Check device/keychain access

## See Also

- [SMS Integration](./SMS_INTEGRATION.md) (similar pattern)
- [WhatsApp Business API Documentation](https://developers.facebook.com/docs/whatsapp)
- [Meta Business Manager](https://business.facebook.com/)

