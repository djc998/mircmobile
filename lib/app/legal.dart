/// The terms people agree to on first launch, and how to reach the people
/// who run IRCage. Shown by `TermsScreen` and Settings → About.
library;

/// Bump when the terms change so everyone is asked to agree again.
const int termsVersion = 1;

/// Where people can reach the app's makers about abuse and anything else.
/// Apple requires published contact information for apps with
/// user-generated content (App Review Guideline 1.2).
const String supportContact = 'support@ircage.com';

/// The terms, as titled sections.
const List<({String title, String body})> termsSections = [
  (
    title: 'What IRCage is',
    body:
        'IRCage connects you to IRC, a public chat system run by '
        "independent networks. We don't run those networks or their rooms, "
        "and we can't see or remove what people write there. Each network "
        'has its own rules and staff, and each room has its own operators.',
  ),
  (
    title: 'No tolerance for abuse',
    body:
        'There is no tolerance for objectionable content or abusive '
        "people. Don't post or send anything illegal, hateful, harassing, "
        'sexual involving minors, threatening, or meant to deceive or '
        'spam. Accounts and rooms that do may be reported to their network, '
        'and photos that break these rules are deleted from our photo '
        'server.',
  ),
  (
    title: 'Keeping yourself safe',
    body:
        'Offensive words are hidden and adult rooms are left out of '
        'Discover; you can change this in Settings → Safety. Ignore anyone '
        'from their profile card to hide their messages, photos and '
        'invitations. Report a message, a photo or a person from its menu.',
  ),
  (
    title: 'Reports',
    body:
        'Reports of messages and photos come to us. We review them within '
        '24 hours, delete photos that break these rules, and pass abuse on '
        "to the network's staff. Room operators and network staff can act "
        'on people directly; Report on a profile shows who to contact.',
  ),
  (
    title: 'Photos and calls',
    body:
        'Photos are encrypted on your device, stripped of location and '
        'other details, and deleted from our server when they expire or '
        'are first viewed. Calls are directly between devices, or through '
        'a relay if you hide your IP address.',
  ),
  (title: 'Contact', body: 'Questions or abuse reports: $supportContact.'),
];
