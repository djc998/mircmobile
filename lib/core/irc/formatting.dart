/// mIRC formatting codes (bold, colours, italics, ...).
library;

final RegExp _formatting = RegExp(
  '\x03(?:\\d{1,2}(?:,\\d{1,2})?)?' // colour with optional fg,bg
  '|\x04(?:[0-9a-fA-F]{6}(?:,[0-9a-fA-F]{6})?)?' // hex colour
  '|[\x02\x0F\x11\x16\x1D\x1E\x1F]',
);

/// Removes mIRC colour and style codes, leaving plain text.
///
/// Used until the coloured renderer lands, and for notifications/search.
String stripFormatting(String text) => text.replaceAll(_formatting, '');

/// Valid IRC nickname: starts with a letter or special, up to 30 chars.
bool isValidNick(String nick) =>
    RegExp(r'^[A-Za-z\[\]\\`_^{|}][A-Za-z0-9\[\]\\`_^{|}-]{0,29}$')
        .hasMatch(nick);
