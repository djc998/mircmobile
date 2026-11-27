#!/usr/bin/env python3
"""A tiny IRC server with friendly made-up rooms and people, for App Store
screenshots and demos. Nothing here is a real network or a real person.

    python3 tool/demo_ircd.py            # listens on 127.0.0.1:6667

In the app: Add your own network -> 127.0.0.1, port 6667, TLS off,
name "Demo". Discover lists the rooms below; joining one plays its chat.
"""

import socket
import threading
import time

HOST, PORT = '127.0.0.1', 6667
NETWORK = 'Demo'

# (room, people, topic)
ROOMS = [
    ('#photography', 214, 'Share your shots, ask about gear, weekly theme: golden hour'),
    ('#coffee', 88, 'Brew methods, beans and morning chat. Be kind, be caffeinated'),
    ('#flutter', 1320, 'Flutter and Dart help. Paste code at a pastebin, not in here'),
    ('#indiegames', 476, 'Making and playing small games. Show-and-tell Fridays'),
    ('#synthwave', 163, 'Retro synths, new releases and listening parties'),
    ('#linux', 2410, 'Linux help and chat. Ask your question, then wait a bit'),
    ('#hiking', 97, 'Trails, trip reports and gear. Leave no trace'),
    ('#bookclub', 61, "This month: a mystery set on a lighthouse. No spoilers before the 20th"),
    ('#retrocomputing', 342, 'Old machines, new tricks. 8-bit to early PCs'),
    ('#help', 512, 'New to IRC? Ask anything, someone will answer'),
    ('#gardening', 129, 'Seeds, soil and harvests. Pictures of tomatoes welcome'),
    ('#chess', 287, 'Puzzles, openings and friendly games'),
    ('#webdev', 905, 'Front end, back end and everything in between'),
    ('#movies', 233, 'What are you watching tonight?'),
]

PEOPLE = {
    '#photography': ['@mira', '@jonah', '+sam_k', 'lena', 'theo', 'ana_r',
                     'kofi', 'ravi', 'ingrid', 'pablo', 'yuki', 'maeve'],
}

# What's said after you join: (delay in seconds, nick, text). \x02 bold,
# \x03 colours, \x01ACTION for /me.
SCRIPT = {
    '#photography': [
        (0.2, 'mira', 'Morning all! This week\'s theme is \x02golden hour\x02 \U0001F305'),
        (0.2, 'jonah', 'Got out at 6 today, the light over the harbour was unreal'),
        (0.2, 'lena', 'Jealous. Overcast here all week'),
        (0.2, 'theo', 'Anyone tried the new 35mm f/1.4? Thinking of switching from the 50'),
        (0.2, 'sam_k', 'I have it. Sharper wide open than the old one, a bit heavier'),
        (0.2, 'theo', 'Good to know, thanks!'),
        (0.2, 'ana_r', '\x01ACTION uploads a sunset from the pier\x01'),
        (0.2, 'mira', 'That colour \U0001F525 what white balance did you use?'),
        (0.2, 'ana_r', 'Daylight, then warmed it a touch in editing'),
        (0.2, 'kofi', 'Reminder: photo walk on Saturday, meet at the old station at 7'),
        (0.2, 'jonah', '\x0303I\'m in\x03, bringing the tripod this time'),
    ],
    '#coffee': [
        (0.2, 'priya', 'Day three of the new grinder and I can finally taste the difference'),
        (0.2, 'marco', 'Told you! Burr grinders change everything ☕'),
    ],
    '#synthwave': [
        (0.2, 'neon_fox', 'Listening party tonight at 9, bring your favourite B-sides'),
    ],
    '#indiegames': [
        (0.2, 'pixelpete', 'Pushed a new build of my puzzle game, would love some testers'),
        (0.2, 'june', 'Count me in, send the link!'),
    ],
}

# Who answers private messages (not services such as NickServ), and what
# they say, in order.
DM_PEOPLE = {'mira', 'jonah', 'kofi', 'lena', 'theo', 'ana_r', 'sam_k'}
DM_REPLIES = [
    'Hey! Yes, Saturday at 7, by the clock tower',
    'Bring a wide lens if you have one, the station hall is huge',
]


def topic(room):
    return next((t for r, _, t in ROOMS if r == room), 'Welcome!')


def handle(conn):
    f = conn.makefile('r', encoding='utf-8', errors='replace')
    nick = 'guest'
    dm_count = {}

    def send(line):
        try:
            conn.sendall((line + '\r\n').encode())
        except OSError:
            pass

    def later(lines):
        def run():
            for delay, who, text in lines:
                time.sleep(delay)
                send(text if who is None else f':{who}!{who}@demo PRIVMSG {text}')
        threading.Thread(target=run, daemon=True).start()

    for raw in f:
        line = raw.strip()
        parts = line.split(' ')
        cmd = parts[0].upper()
        if cmd == 'CAP' and len(parts) > 1 and parts[1].upper() == 'LS':
            send(':demo CAP * LS :')
        elif cmd == 'NICK':
            nick = parts[1]
        elif cmd == 'USER':
            send(f':demo 001 {nick} :Welcome to the {NETWORK} network, {nick}')
            send(f':demo 005 {nick} CHANTYPES=# PREFIX=(ov)@+ NETWORK={NETWORK} '
                 'SAFELIST ELIST=U :are supported')
            send(f':demo 375 {nick} :- demo Message of the day -')
            send(f':demo 372 {nick} :- A pretend network for trying IRCage.')
            send(f':demo 376 {nick} :End of /MOTD command.')
        elif cmd == 'PING':
            send(f':demo PONG demo :{parts[-1].lstrip(":")}')
        elif cmd == 'LIST':
            send(f':demo 321 {nick} Channel :Users  Name')
            for room, people, t in ROOMS:
                send(f':demo 322 {nick} {room} {people} :{t}')
            send(f':demo 323 {nick} :End of /LIST')
        elif cmd == 'JOIN':
            for room in parts[1].split(','):
                send(f':{nick}!{nick}@demo JOIN {room}')
                send(f':demo 332 {nick} {room} :{topic(room)}')
                names = PEOPLE.get(room, ['@host', 'alex', 'jo'])
                send(f':demo 353 {nick} = {room} :{nick} ' + ' '.join(names))
                send(f':demo 366 {nick} {room} :End of /NAMES list.')
                later([(d, who, f'{room} :{text}')
                       for d, who, text in SCRIPT.get(room, [])])
        elif cmd == 'PRIVMSG' and len(parts) > 2 and parts[1] in DM_PEOPLE:
            who = parts[1]
            n = dm_count.get(who, 0)
            dm_count[who] = n + 1
            if n < len(DM_REPLIES):
                later([(1.5, who, f'{nick} :{DM_REPLIES[n]}')])
        elif cmd == 'WHOIS' and len(parts) > 1:
            who = parts[-1]
            send(f':demo 311 {nick} {who} {who} demo * :{who.capitalize()}')
            send(f':demo 318 {nick} {who} :End of /WHOIS list.')
        elif cmd == 'QUIT':
            break
    conn.close()


def main():
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen()
    print(f'Demo IRC server on {HOST}:{PORT}', flush=True)
    while True:
        conn, _ = server.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()


if __name__ == '__main__':
    main()
