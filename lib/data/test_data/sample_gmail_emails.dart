import 'package:actionmail/data/models/gmail_message.dart';

/// Sample Gmail API email data for testing
/// Matches actual Gmail API response format with labelIds only
class SampleGmailEmails {

  /// Generate sample Gmail API messages
  /// These simulate what we'd get from Gmail API
  static List<GmailMessage> generateSampleGmailMessages() {
    final now = DateTime.now();
    final timestampNow = now.millisecondsSinceEpoch;
    
    return [
      // Email with action date - bill due
      GmailMessage(
        id: 'msg001',
        threadId: 'thread001',
        labelIds: ['INBOX', 'UNREAD', 'CATEGORY_BILLS'],
        snippet: 'Please pay your bill by 30 April. Your amount due is \$150.00.',
        historyId: 'hist001',
        internalDate: timestampNow - (2 * 24 * 60 * 60 * 1000), // 2 days ago
        payload: MessagePayload(
          headers: [
            MessageHeader(name: 'From', value: 'billing@utilityco.com'),
            MessageHeader(name: 'To', value: 'user@example.com'),
            MessageHeader(name: 'Subject', value: 'October Bill Available - Due 30 Apr'),
            MessageHeader(name: 'Date', value: 'Mon, 28 Oct 2024 10:00:00 +0000'),
          ],
          body: null,
          mimeType: 'text/plain',
        ),
        sizeEstimate: 1234,
      ),
      
      // Shopping email with delivery date
      GmailMessage(
        id: 'msg002',
        threadId: 'thread002',
        labelIds: ['INBOX', 'UNREAD', 'CATEGORY_PURCHASES'],
        snippet: 'Expected delivery on Tuesday, 5 November. Track your package.',
        historyId: 'hist002',
        internalDate: timestampNow - (1 * 24 * 60 * 60 * 1000), // 1 day ago
        payload: MessagePayload(
          headers: [
            MessageHeader(name: 'From', value: 'orders@amazon.com'),
            MessageHeader(name: 'To', value: 'user@example.com'),
            MessageHeader(name: 'Subject', value: 'Your order has shipped'),
            MessageHeader(name: 'Date', value: 'Tue, 29 Oct 2024 14:30:00 +0000'),
          ],
        ),
        sizeEstimate: 2345,
      ),
      
      // Email with attachment (starred and important)
      GmailMessage(
        id: 'msg003',
        threadId: 'thread003',
        labelIds: ['INBOX', 'STARRED', 'IMPORTANT', 'CATEGORY_PERSONAL'],
        snippet: 'Please review the attached Q4 report and provide feedback by Friday.',
        historyId: 'hist003',
        internalDate: timestampNow - (3 * 24 * 60 * 60 * 1000), // 3 days ago
        payload: MessagePayload(
          headers: [
            MessageHeader(name: 'From', value: 'team@company.com'),
            MessageHeader(name: 'To', value: 'user@example.com'),
            MessageHeader(name: 'Subject', value: 'Q4 Report - Please Review'),
            MessageHeader(name: 'Date', value: 'Sat, 26 Oct 2024 09:15:00 +0000'),
          ],
          parts: [
            MessagePart(
              mimeType: 'text/plain',
              headers: [],
              body: MessageBody(data: 'Please review...', size: 256),
            ),
            MessagePart(
              mimeType: 'application/pdf',
              filename: 'Q4_Report.pdf',
              headers: [],
              body: MessageBody(attachmentId: 'att001', size: 45678),
            ),
          ],
          mimeType: 'multipart/mixed',
        ),
        sizeEstimate: 45934,
      ),
      
      // Email without detected action (newsletter)
      GmailMessage(
        id: 'msg004',
        threadId: 'thread004',
        labelIds: ['INBOX', 'UNREAD', 'CATEGORY_UPDATES'],
        snippet: 'Here are the top stories from this week...',
        historyId: 'hist004',
        internalDate: timestampNow - (5 * 60 * 60 * 1000), // 5 hours ago
        payload: MessagePayload(
          headers: [
            MessageHeader(name: 'From', value: 'newsletter@daily.com'),
            MessageHeader(name: 'To', value: 'user@example.com'),
            MessageHeader(name: 'Subject', value: 'Your weekly digest'),
            MessageHeader(name: 'Date', value: 'Tue, 30 Oct 2024 07:00:00 +0000'),
          ],
        ),
        sizeEstimate: 3456,
      ),
      
      // Overdue action email (important, read)
      GmailMessage(
        id: 'msg005',
        threadId: 'thread005',
        labelIds: ['INBOX', 'IMPORTANT', 'CATEGORY_PERSONAL'],
        snippet: 'Please update your emergency contact information by 25 October.',
        historyId: 'hist005',
        internalDate: timestampNow - (10 * 24 * 60 * 60 * 1000), // 10 days ago
        payload: MessagePayload(
          headers: [
            MessageHeader(name: 'From', value: 'hr@company.com'),
            MessageHeader(name: 'To', value: 'user@example.com'),
            MessageHeader(name: 'Subject', value: 'Please update your emergency contact'),
            MessageHeader(name: 'Date', value: 'Sat, 20 Oct 2024 11:00:00 +0000'),
          ],
        ),
        sizeEstimate: 1789,
      ),
      
      // Finance email (read)
      GmailMessage(
        id: 'msg006',
        threadId: 'thread006',
        labelIds: ['INBOX', 'CATEGORY_FINANCE'],
        snippet: 'A transaction of \$45.00 was made at Coffee Shop.',
        historyId: 'hist006',
        internalDate: timestampNow - (12 * 60 * 60 * 1000), // 12 hours ago
        payload: MessagePayload(
          headers: [
            MessageHeader(name: 'From', value: 'alerts@bank.com'),
            MessageHeader(name: 'To', value: 'user@example.com'),
            MessageHeader(name: 'Subject', value: 'Transaction Alert'),
            MessageHeader(name: 'Date', value: 'Mon, 29 Oct 2024 22:00:00 +0000'),
          ],
        ),
        sizeEstimate: 890,
      ),
      
      // Social email (unread)
      GmailMessage(
        id: 'msg007',
        threadId: 'thread007',
        labelIds: ['INBOX', 'UNREAD', 'CATEGORY_SOCIAL'],
        snippet: 'John Smith commented on your recent post about...',
        historyId: 'hist007',
        internalDate: timestampNow - (1 * 60 * 60 * 1000), // 1 hour ago
        payload: MessagePayload(
          headers: [
            MessageHeader(name: 'From', value: 'Social Media <noreply@socialmedia.com>'),
            MessageHeader(name: 'To', value: 'user@example.com'),
            MessageHeader(name: 'Subject', value: 'John commented on your post'),
            MessageHeader(name: 'Date', value: 'Tue, 30 Oct 2024 11:00:00 +0000'),
          ],
        ),
        sizeEstimate: 567,
      ),
      
      // Promotion email (unread)
      GmailMessage(
        id: 'msg008',
        threadId: 'thread008',
        labelIds: ['INBOX', 'UNREAD', 'CATEGORY_PROMOTIONS'],
        snippet: 'Don\'t miss our biggest sale of the year. Use code SAVE50.',
        historyId: 'hist008',
        internalDate: timestampNow - (3 * 24 * 60 * 60 * 1000), // 3 days ago
        payload: MessagePayload(
          headers: [
            MessageHeader(name: 'From', value: 'deals@store.com'),
            MessageHeader(name: 'To', value: 'user@example.com'),
            MessageHeader(name: 'Subject', value: '50% Off Sale This Weekend!'),
            MessageHeader(name: 'Date', value: 'Sat, 27 Oct 2024 08:00:00 +0000'),
          ],
        ),
        sizeEstimate: 2341,
      ),
      
      // Travel email (starred, read)
      GmailMessage(
        id: 'msg009',
        threadId: 'thread009',
        labelIds: ['INBOX', 'STARRED', 'CATEGORY_TRAVEL'],
        snippet: 'Flight AA1234 on December 15, 2024. Check-in opens 24 hours before departure.',
        historyId: 'hist009',
        internalDate: timestampNow - (5 * 24 * 60 * 60 * 1000), // 5 days ago
        payload: MessagePayload(
          headers: [
            MessageHeader(name: 'From', value: 'confirmation@airline.com'),
            MessageHeader(name: 'To', value: 'user@example.com'),
            MessageHeader(name: 'Subject', value: 'Your flight confirmation'),
            MessageHeader(name: 'Date', value: 'Thu, 25 Oct 2024 16:45:00 +0000'),
          ],
          parts: [
            MessagePart(
              mimeType: 'text/html',
              headers: [],
              body: MessageBody(data: 'Flight confirmation...', size: 3456),
            ),
            MessagePart(
              mimeType: 'application/pdf',
              filename: 'ticket.pdf',
              headers: [],
              body: MessageBody(attachmentId: 'att002', size: 123456),
            ),
          ],
          mimeType: 'multipart/mixed',
        ),
        sizeEstimate: 126912,
      ),
      
      // Receipt email (read)
      GmailMessage(
        id: 'msg010',
        threadId: 'thread010',
        labelIds: ['INBOX', 'CATEGORY_RECEIPTS'],
        snippet: 'Thank you for your purchase. Your receipt is attached.',
        historyId: 'hist010',
        internalDate: timestampNow - (3 * 60 * 60 * 1000), // 3 hours ago
        payload: MessagePayload(
          headers: [
            MessageHeader(name: 'From', value: 'receipts@store.com'),
            MessageHeader(name: 'To', value: 'user@example.com'),
            MessageHeader(name: 'Subject', value: 'Receipt for your purchase'),
            MessageHeader(name: 'Date', value: 'Tue, 30 Oct 2024 09:00:00 +0000'),
          ],
          parts: [
            MessagePart(
              mimeType: 'text/plain',
              headers: [],
              body: MessageBody(data: 'Thank you...', size: 234),
            ),
            MessagePart(
              mimeType: 'application/pdf',
              filename: 'receipt.pdf',
              headers: [],
              body: MessageBody(attachmentId: 'att003', size: 56789),
            ),
          ],
          mimeType: 'multipart/mixed',
        ),
        sizeEstimate: 57023,
      ),

      // Sent email
      GmailMessage(
        id: 'msg011',
        threadId: 'thread011',
        labelIds: ['SENT'],
        snippet: 'Following up on our meeting notes from yesterday.',
        historyId: 'hist011',
        internalDate: timestampNow - (6 * 60 * 60 * 1000),
        payload: MessagePayload(
          headers: [
            MessageHeader(name: 'From', value: 'user@example.com'),
            MessageHeader(name: 'To', value: 'team@company.com'),
            MessageHeader(name: 'Subject', value: 'Follow-up: Meeting notes'),
            MessageHeader(name: 'Date', value: 'Tue, 30 Oct 2024 06:00:00 +0000'),
          ],
          mimeType: 'text/plain',
        ),
        sizeEstimate: 1400,
      ),

      // Trash email
      GmailMessage(
        id: 'msg012',
        threadId: 'thread012',
        labelIds: ['TRASH', 'UNREAD'],
        snippet: 'You won a prize! Click here to claim...',
        historyId: 'hist012',
        internalDate: timestampNow - (2 * 24 * 60 * 60 * 1000),
        payload: MessagePayload(
          headers: [
            MessageHeader(name: 'From', value: 'scam@phish.com'),
            MessageHeader(name: 'To', value: 'user@example.com'),
            MessageHeader(name: 'Subject', value: 'Congrats!'),
            MessageHeader(name: 'Date', value: 'Sun, 28 Oct 2024 12:00:00 +0000'),
          ],
        ),
        sizeEstimate: 700,
      ),

      // Spam email
      GmailMessage(
        id: 'msg013',
        threadId: 'thread013',
        labelIds: ['SPAM', 'UNREAD'],
        snippet: 'Make money fast with this one simple trick...',
        historyId: 'hist013',
        internalDate: timestampNow - (4 * 24 * 60 * 60 * 1000),
        payload: MessagePayload(
          headers: [
            MessageHeader(name: 'From', value: 'spam@mailer.com'),
            MessageHeader(name: 'To', value: 'user@example.com'),
            MessageHeader(name: 'Subject', value: 'Earn \$\$\$ fast'),
            MessageHeader(name: 'Date', value: 'Fri, 26 Oct 2024 15:00:00 +0000'),
          ],
        ),
        sizeEstimate: 800,
      ),

      // Archived email
      GmailMessage(
        id: 'msg014',
        threadId: 'thread014',
        labelIds: ['ARCHIVE'],
        snippet: 'Project proposal approved. Next steps attached.',
        historyId: 'hist014',
        internalDate: timestampNow - (8 * 24 * 60 * 60 * 1000),
        payload: MessagePayload(
          headers: [
            MessageHeader(name: 'From', value: 'manager@company.com'),
            MessageHeader(name: 'To', value: 'user@example.com'),
            MessageHeader(name: 'Subject', value: 'Proposal approved'),
            MessageHeader(name: 'Date', value: 'Mon, 22 Oct 2024 10:30:00 +0000'),
          ],
        ),
        sizeEstimate: 2200,
      ),
    ];
  }
}

