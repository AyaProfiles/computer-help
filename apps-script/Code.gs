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

  // Automatic reports (daily log, silent checks) say quiet: they are saved to Drive but not emailed.
  if (!data.quiet) MailApp.sendEmail(Session.getEffectiveUser().getEmail(),
                    'Computer Help: ' + data.who + (data.note ? ' - ' + data.note.slice(0, 60) : ''),
                    text + '\n\nSaved in Drive: ' + FOLDER_NAME + '/' + name);
  trashOldReports();
  return ContentService.createTextOutput('ok');
}

// Moves report files older than KEEP_DAYS to the Drive trash (Drive empties its trash after 30 more days).
// Runs at most once a day, whenever a report arrives. Only touches files named like the ones saved above.
const KEEP_DAYS = 30;
function trashOldReports() {
  const props = PropertiesService.getScriptProperties();
  const today = Utilities.formatDate(new Date(), Session.getScriptTimeZone(), 'yyyy-MM-dd');
  if (props.getProperty('lastCleanup') === today) return;
  props.setProperty('lastCleanup', today);
  const cutoff = Date.now() - KEEP_DAYS * 24 * 3600 * 1000;
  const files = getFolder().getFiles();
  while (files.hasNext()) {
    const f = files.next();
    if (/^\d{4}-\d{2}-\d{2} \d{4} /.test(f.getName()) && f.getDateCreated().getTime() < cutoff) f.setTrashed(true);
  }
}

function getFolder() {
  const found = DriveApp.getFoldersByName(FOLDER_NAME);
  return found.hasNext() ? found.next() : DriveApp.createFolder(FOLDER_NAME);
}
