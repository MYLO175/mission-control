#!/usr/bin/osascript -l JavaScript
// Read Mail headers or a single message body. Input is one JSON argument;
// stdout is exactly one JSON object so Swift can decode it directly.

ObjC.import('Foundation');

function jsonOutput(value) {
    const data = $.NSJSONSerialization.dataWithJSONObjectOptionsError(
        value, $.NSJSONWritingFragmentsAllowed, null
    );
    if (!data) throw new Error('Could not encode JSON output');
    return ObjC.unwrap($.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding));
}

function stringValue(value) {
    if (value === null || value === undefined) return '';
    return String(ObjC.unwrap(value));
}

function listValue(value) {
    if (value === null || value === undefined) return [];
    return Array.isArray(value) ? value : [value];
}

function dateISO(value) {
    if (!value) return null;
    const seconds = value instanceof Date
        ? value.getTime() / 1000
        : Number(ObjC.unwrap(value).timeIntervalSince1970());
    if (!Number.isFinite(seconds)) return null;
    return new Date(seconds * 1000).toISOString();
}

function accountError(accountID, message) {
    const label = accountID ? 'Account ' + accountID : 'Mail';
    return label + ': ' + String(message);
}

function resolveInbox(mail, account, accountID) {
    // Resolve an account's exact Inbox, rather than an aggregate child mailbox.
    // Resolve the specifier now. Leaving an indexed mailbox unevaluated makes
    // Mail repeat expensive account/mailbox resolution on every property read.
    const names = listValue(account.mailboxes.name());
    for (let i = 0; i < names.length; i += 1) {
        if (stringValue(names[i]).toLowerCase() === 'inbox') return account.mailboxes[i]();
    }
    throw new Error('Inbox mailbox not found for this account');
}

function resolveSearchMailbox(mail, account, input) {
    if (!input.mailboxName) return resolveInbox(mail, account, input.accountID);
    const requested = String(input.mailboxName);
    if (!requested || requested.length > 500) throw new Error('Invalid mailbox name');
    const names = listValue(account.mailboxes.name());
    const matches = names.map((name,index) => ({ name: stringValue(name), index: index })).filter(value => value.name === requested);
    if (matches.length !== 1) throw new Error('The exact account mailbox changed or is ambiguous; search again');
    return account.mailboxes[matches[0].index]();
}
function searchFolders(mail) {
    const folders = [], accounts = [], errors = [];
    mail.accounts().forEach(function(account) {
        const id = stringValue(account.id());
        try {
            if (!account.enabled()) return;
            const title = stringValue(account.name());
            accounts.push({id:id,title:title});
            const names = listValue(account.mailboxes.name());
            if (names.length > 500) throw new Error('Too many top-level mailboxes for bounded discovery');
            names.forEach(function(raw) {
                const name = stringValue(raw), lower = name.toLowerCase();
                let role = null;
                if (lower === 'inbox') role = 'inbox';
                else if (['sent','sent messages','sent items'].indexOf(lower) >= 0) role = 'sent';
                else if (lower === 'archive' || lower === 'archives') role = 'archive';
                if (role) folders.push({ id:id + ':' + name, accountID:id, account:title, name:name, role:role });
            });
        } catch(error) { errors.push(accountError(id,error)); }
    });
    return { folders:folders, accounts:accounts, errors:errors };
}

function runHeaders(mail, input) {
    const accounts = [];
    const messages = [];
    const errors = [];
    const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
    let sourceAccounts;

    try {
        sourceAccounts = mail.accounts();
    } catch (error) {
        return { messages: [], accounts: [], errors: [accountError(null, error)] };
    }

    sourceAccounts.forEach(function (account) {
        let accountID = null;
        let title = 'Mail account';
        try {
            if (!account.enabled()) return;
            accountID = stringValue(account.id());
            if (input.accountID && String(input.accountID) !== accountID) return;
            title = stringValue(account.name()) || title;
            const inbox = resolveInbox(mail, account, accountID);
            // Ask Mail to filter by date before fetching properties. Then each
            // property is requested for the whole result set in one Apple event.
            const recent = inbox.messages.whose({ dateReceived: { _greaterThan: cutoff } });
            const ids = listValue(recent.id());
            const internetIDs = listValue(recent.messageId());
            const senders = listValue(recent.sender());
            const subjects = listValue(recent.subject());
            const dates = listValue(recent.dateReceived());
            const unread = listValue(recent.readStatus());
            const replied = listValue(recent.wasRepliedTo());
            const flagged = listValue(recent.flaggedStatus());
            const count = ids.length;
            const accountMessages = [];

            for (let i = 0; i < count; i += 1) {
                const messageID = Number(ids[i]);
                const received = dateISO(dates[i]);
                if (!Number.isFinite(messageID) || !received) continue;
                accountMessages.push({
                    id: accountID + ':' + String(messageID),
                    accountID: accountID,
                    account: title,
                    messageID: messageID,
                    internetMessageID: stringValue(internetIDs[i]),
                    sender: stringValue(senders[i]),
                    subject: stringValue(subjects[i]),
                    received: received,
                    unread: !Boolean(unread[i]),
                    replied: Boolean(replied[i]),
                    flagged: Boolean(flagged[i])
                });
            }
            messages.push.apply(messages, accountMessages);
            accounts.push({ id: accountID, title: title });
        } catch (error) {
            errors.push(accountError(accountID, error));
        }
    });

    return { messages: messages, accounts: accounts, errors: errors };
}

function runBody(mail, input) {
    const accountID = String(input.accountID || '');
    const messageID = Number(input.messageID);
    if (!accountID || !Number.isSafeInteger(messageID) || messageID < 0) {
        return { body: '', internetMessageID: '', errors: [accountError(accountID, 'Invalid accountID or messageID')] };
    }

    try {
        const account = mail.accounts.byId(accountID)();
        if (!account || !account.enabled()) throw new Error('Enabled Mail account not found');
        const inbox = resolveSearchMailbox(mail, account, input);
        const message = inbox.messages.byId(messageID)();
        if (!message) throw new Error('Message not found in its original account mailbox');
        const identityBefore = stringValue(message.messageId());
        if (input.expectedInternetMessageID && String(input.expectedInternetMessageID) !== identityBefore) {
            throw new Error('Message identity changed; refresh before previewing');
        }
        const unreadBefore = previewUnread(message);
        const body = stringValue(message.content());
        const unreadAfter = previewUnread(message);
        const identityAfter = stringValue(message.messageId());
        if (identityBefore !== identityAfter) throw new Error('Message identity changed during preview retrieval');
        if (unreadBefore !== unreadAfter) throw new Error('Mail changed the read state during preview retrieval');
        return {
            body: body,
            unreadBefore: unreadBefore,
            unreadAfter: unreadAfter,
            internetMessageID: identityAfter,
            errors: []
        };
    } catch (error) {
        return { body: '', internetMessageID: '', errors: [accountError(accountID, error)] };
    }
}

function previewUnread(message) {
    const value = ObjC.unwrap(message.readStatus());
    if (typeof value === 'boolean') return !value;
    // NSNumber bridges can expose the Boolean as 0/1. Missing/other values
    // cannot establish preservation and must not be guessed as unread.
    if (value === 0 || value === 1) return value === 0;
    throw new Error('Mail read state is unavailable; preview was not verified');
}

// Resolve one date window once, then paginate a persisted list of message IDs.
// Array.slice below is ordinary JavaScript; never use Mail's indexed range
// specifier, which can copy the whole inbox once for every selected index.
function runBatch(mail, input) {
    const accountID = String(input.accountID || '');
    const start = new Date(Number(input.start) * 1000);
    const end = new Date(Number(input.end) * 1000);
    const offset = Number(input.offset || 0);
    const limit = Math.min(20, Number(input.limit || 20));
    if (!accountID || !Number.isFinite(start.getTime()) || !(start < end) || !Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(limit) || limit < 1) throw new Error('Invalid Mail batch');
    const account = mail.accounts.byId(accountID)();
    if (!account.enabled()) throw new Error('Mail account is unavailable');
    const inbox = resolveSearchMailbox(mail, account, input);
    const dateField = input.mailboxRole === 'sent' ? 'dateSent' : 'dateReceived';
    let ids = input.messageIDs;
    let retainedIDs = [];
    if (!Array.isArray(ids)) {
        // Apple-event dates have whole-second precision. Round the native
        // predicate outwards, then keep only the exact captured logical range.
        const queryStart = new Date(Math.floor(start.getTime() / 1000) * 1000);
        const queryEnd = new Date(Math.ceil(end.getTime() / 1000) * 1000);
        const exactDateFilter = queryStart.getTime() !== start.getTime() || queryEnd.getTime() !== end.getTime();
        const lower = {}, upper = {}; lower[dateField] = { _greaterThanEquals:queryStart }; upper[dateField] = { _lessThan:queryEnd };
        const dated = inbox.messages.whose({ _and:[lower,upper] });
        // A property read on an unresolved `whose` repeats the date query.
        // Resolve once when comparing several fields. The resolved references
        // keep native IDs; continuation pages still reuse the persisted ID list.
        let resolved = exactDateFilter || input.knownMessages || (input.searchTerms && input.mailboxRole !== 'sent') ? listValue(dated()) : null;
        const values = property => resolved ? resolved.map(message => message[property]()) : listValue(dated[property]());
        ids = values('id').map(Number);
        if (exactDateFilter) {
            const dates = values(dateField).map(dateISO);
            const checkedIDs = values('id').map(Number);
            if (dates.length !== ids.length || checkedIDs.length !== ids.length || checkedIDs.some((id,index) => id !== ids[index]) || dates.some(date => !date || new Date(date) < queryStart || new Date(date) >= queryEnd)) throw new Error('Mailbox dates changed or moved; retry this date window');
            const exactMatches = dates.map(date => new Date(date) >= start && new Date(date) < end);
            resolved = resolved.filter((message,index) => exactMatches[index]);
            ids = ids.filter((id,index) => exactMatches[index]);
        }
        if (input.knownMessages) {
            const internetIDs=values('messageId');
            const checkedIDs=values('id').map(Number);
            if(internetIDs.length!==ids.length||checkedIDs.length!==ids.length||checkedIDs.some((id,index)=>id!==ids[index])) throw new Error('Mailbox identities changed or moved; retry this date window');
            retainedIDs=ids.filter((id,index)=>input.knownMessages[String(id)]===stringValue(internetIDs[index]));
            const retained=new Set(retainedIDs);
            ids=ids.filter(id=>!retained.has(id));
        }
        if (input.searchTerms && input.mailboxRole !== 'sent') {
            if (!Array.isArray(input.searchTerms) || !input.searchTerms.length || input.searchTerms.length > 5 || input.searchTerms.some(term => typeof term !== 'string' || term.length < 2 || term.length > 80)) throw new Error('Invalid header search terms');
            const terms = input.searchTerms.map(term => term.toLowerCase());
            const subjects = values('subject'), senders = values('sender');
            const checkedIDs = values('id').map(Number);
            if (subjects.length !== ids.length || senders.length !== ids.length || checkedIDs.length !== ids.length || checkedIDs.some((id,index) => id !== ids[index])) throw new Error('Mailbox headers changed or moved during search; retry this date window');
            ids = ids.filter((id,index) => terms.some(term => stringValue(subjects[index]).toLowerCase().includes(term) || stringValue(senders[index]).toLowerCase().includes(term)));
        }
    }
    if (ids.some(id => !Number.isSafeInteger(id) || id < 0)) throw new Error('Invalid message identity in batch');
    const title = stringValue(account.name());
    const page = ids.slice(offset, offset + limit);
    const messages = page.map(function (id) {
        const message = inbox.messages.byId(id)();
        const received = dateISO(input.mailboxRole === 'sent' ? message.dateSent() : message.dateReceived());
        if (!received || new Date(received) < start || new Date(received) >= end) throw new Error('A message changed or moved; retry this date window');
        let recipients = null;
        if (input.mailboxRole === 'sent') {
            const addresses = listValue(message.toRecipients.address()), names = listValue(message.toRecipients.name());
            recipients = addresses.slice(0,50).map((address,index) => stringValue(names[index]) + ' <' + stringValue(address) + '>');
        }
        return { id: accountID + ':' + id, accountID: accountID, account: title, messageID: id,
            internetMessageID: stringValue(message.messageId()), sender: stringValue(message.sender()),
            subject: stringValue(message.subject()), received: received, unread: !Boolean(message.readStatus()),
            replied: Boolean(message.wasRepliedTo()), flagged: Boolean(message.flaggedStatus()), mailboxName:input.mailboxName ? String(input.mailboxName) : null, mailboxRole:input.mailboxRole || null, recipients:recipients };
    });
    return { messages: messages, messageIDs: ids, nextOffset: offset + page.length,
        complete: offset + page.length >= ids.length, retainedIDs:retainedIDs, errors: [] };
}

function probeInboxes(mail) {
    const accounts = [], errors = [], unavailableAccounts = [], accountErrors = {};
    mail.accounts().forEach(function(account) {
        if (!account.enabled()) return;
        const id = stringValue(account.id());
        try { accounts.push({ id: id, title: stringValue(account.name()), inbox: stringValue(resolveInbox(mail, account, id).name()) }); }
        catch (error) {
            const detail=accountError(id, error);errors.push(detail);accountErrors[id]=detail;
            let title=id;try {title=stringValue(account.name())||id;}catch (_){}
            unavailableAccounts.push({id:id,title:title});
        }
    });
    return { accounts: accounts, errors: errors, unavailableAccounts:unavailableAccounts, accountErrors:accountErrors };
}
function probeDates(mail,input) {
    return {checks:mail.accounts().filter(account=>account.enabled()).map(account=>{
        const accountID=stringValue(account.id());
        const inbox=resolveInbox(mail,account,accountID);
        const start=new Date(Number(input.start)*1000),end=new Date(Number(input.end)*1000);
        const dated=inbox.messages.whose({_and:[{dateReceived:{_greaterThanEquals:start}},{dateReceived:{_lessThan:end}}]});
        const bulk=listValue(dated.id()).map(Number);
        const resolved=listValue(dated()).map(message=>Number(message.id()));
        return {bulkCount:bulk.length,resolvedCount:resolved.length,sameIDs:bulk.length===resolved.length&&bulk.every(id=>resolved.includes(id))};
    })};
}
function run(argv) {
    try {
        if (!argv || argv.length !== 1) {
            throw new Error('Expected exactly one JSON argument');
        }
        const input = JSON.parse(argv[0]);
        const mail = Application('Mail');
        let output;
        if (input.operation === 'probe-dates') {
            output=probeDates(mail,input);
        } else if (input.operation === 'folders') {
            output = searchFolders(mail);
        } else if (input.operation === 'batch') {
            output = runBatch(mail, input);
        } else if (input.operation === 'probe') {
            output = probeInboxes(mail);
        } else if (input.operation === 'headers') {
            output = runHeaders(mail, input);
        } else if (input.operation === 'body') {
            output = runBody(mail, input);
        } else {
            output = { messages: [], accounts: [], errors: [accountError(null, 'Unsupported operation')] };
        }
        return jsonOutput(output);
    } catch (error) {
        return jsonOutput({ messages: [], accounts: [], errors: [accountError(null, error)] });
    }
}
