// Computer Help receiver: a Google Apps Script web app in Brad's Google account.
// The in-laws' PC POSTs a report here; it is saved to Drive and emailed to Brad.
// Deploy: Deploy > New deployment > Web app, Execute as: Me, Who has access: Anyone.
const KEY = 'CHANGE-ME-TO-A-LONG-RANDOM-STRING';
const FOLDER_NAME = 'Computer Help reports';

function doPost(e) {
  const data = JSON.parse(e.postData.contents);
  if (data.key !== KEY) return ContentService.createTextOutput('denied');

  const stamp = Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'yyyy-MM-dd HHmm');
  const name = stamp + ' ' + (data.who || 'unknown') + '.txt';
  const text = 'From: ' + data.who + '\nTool version: ' + data.version +
               '\nWhat they wrote: ' + (data.note || '(nothing)') + '\n\n' + data.report;
  getFolder().createFile(name, text, MimeType.PLAIN_TEXT);
  // The 14-day history (one line every 5 minutes) goes next to the report.
  if (data.history) getFolder().createFile(name.replace(/\.txt$/, ' history.csv'), data.history, MimeType.CSV);

  MailApp.sendEmail(Session.getEffectiveUser().getEmail(),
                    'Computer Help: ' + data.who + (data.note ? ' - ' + data.note.slice(0, 60) : ''),
                    text + '\n\nSaved in Drive: ' + FOLDER_NAME + '/' + name);
  return ContentService.createTextOutput('ok');
}

function getFolder() {
  const found = DriveApp.getFoldersByName(FOLDER_NAME);
  return found.hasNext() ? found.next() : DriveApp.createFolder(FOLDER_NAME);
}
