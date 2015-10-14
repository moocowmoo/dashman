#!/usr/bin/env python

import curses
import datetime
import json
import os
import re
import subprocess
import sys
import termios
import time
import tty


VERSION = '0.0.1'
git_dir = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
dash_conf_dir = os.path.join(os.getenv('HOME'), '.dash')

sys.path.append(git_dir + '/lib')
import dashutil


def getch():
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        ch = sys.stdin.read(1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    return ch


def random_timestamp():
    now_epoch = int(time.time())
    random = map(ord, os.urandom(4))
    offset = 0
    for d in range(4):
        offset += pow(random[d], 2**d)
    return now_epoch - (offset % 86400)


def run_command(cmd):
    return subprocess.check_output(cmd, shell=True)


def next_vote(sel_ent):
    sel_ent += 1
    if sel_ent > votecount:
        sel_ent = 0
    return sel_ent


def prev_vote(sel_ent):
    sel_ent -= 1
    if sel_ent < 0:
        sel_ent = votecount
    return sel_ent


def set_vote(b, s, dir):
    if s >= votecount:
        return s
    votes = ['NO', 'ABSTAIN', 'YES']
    vote_idx = {'NO': 0, 'ABSTAIN': 1, 'YES': 2}
    cur_vote = b[ballot_entries[s]][u'vote']
    b[ballot_entries[s]][u'vote'] = votes[
        (vote_idx[cur_vote] + dir) % len(votes)]
    return s


def update_vote_display(win, sel_ent, vote):
    vote_colors = {
        "YES": C_GREEN,
        "NO": C_RED,
        "ABSTAIN": C_YELLOW,
        '': 3
    }
    if vote == '':
        sel_ent += 1
        win.move(sel_ent + 5, max_proposal_len + 6)
        win.addstr('       ')
        win.move(sel_ent + 5, max_proposal_len + 6)
        win.addstr('CONFIRM', C_GREEN)
        win.move(sel_ent + 5, max_proposal_len + 6)
    else:
        win.move(sel_ent + 5, max_proposal_len + 6)
        win.addstr('       ')
        win.move(sel_ent + 5, max_proposal_len + 6)
        win.addstr(vote, vote_colors[vote])
        win.move(sel_ent + 5, max_proposal_len + 6)


def submit_votes(win, ballot, s):
    if s < votecount:
        return s

    votes_to_send = {}
    for entry in sorted(ballot, key=lambda s: s.lower()):
        if ballot[entry][u'vote'] != 'ABSTAIN':
            votes_to_send[entry] = ballot[entry]

    votewin.clear()
    stdscr.move(0, 0)

    if votes_to_send.keys():
        stdscr.addstr("sending time-randomized votes\n\n", C_GREEN)
        stdscr.refresh()
        for vote in sorted(votes_to_send, key=lambda s: s.lower()):
            castvote = str(votes_to_send[vote][u'vote'])
            stdscr.addstr('  ' + vote, C_YELLOW)
            stdscr.addstr(" --> ")
            stdscr.addstr(castvote, castvote == 'YES' and C_GREEN or C_RED )
            stdscr.addstr("\n")
            for mn in sorted(masternodes):
                node = masternodes[mn]
                random_ts = random_timestamp()
                ts = datetime.datetime.fromtimestamp(random_ts)
                stdscr.addstr('    ' + mn, C_CYAN)
                stdscr.addstr(' ' + str(ts) + ' ', C_YELLOW)
                netvote = str(node['fundtx']) + str(votes_to_send
                                                    [vote][u'Hash']) + str(votes_to_send[vote][u'vote'] ==
                                                                           'YES' and 1 or 2) + str(random_ts)
                mnprivkey = node['mnprivkey']
                signature = dashutil.sign_vote(netvote, mnprivkey)
                command = 'dash-cli mnbudgetvoteraw ' + str(node['txid']) + ' ' + str(node['txout']) + ' ' + str(
                    votes_to_send[vote][u'Hash']) + ' ' + str(votes_to_send[vote][u'vote']).lower() + ' ' + str(random_ts) + ' ' + signature
    #            print netvote + ' ' + signature
    #            print command
                stdout = run_command(command)
                stdscr.addstr(stdout.rstrip("\n") + "\n", 'successfully' in stdout and C_GREEN or C_RED)
                stdscr.refresh()

    stdscr.addstr("\nHit any key to exit." + "\n", C_GREEN)
    stdscr.refresh()
    stdscr.getch()
    quit()


def main(screen):

    global stdscr
    global votecount
    global max_proposal_len
    global ballot_entries
    global votewin
    global masternodes
    global C_YELLOW, C_GREEN, C_RED, C_CYAN

    stdscr = screen
    stdscr.scrollok(1)

    try:
        curses.curs_set(2)
    except:
        pass
    if curses.has_colors():
        curses.start_color()
        curses.use_default_colors()
        for i in range(0, curses.COLORS):
            curses.init_pair(i + 1, i, -1)

    C_CYAN = curses.color_pair(7)
    C_YELLOW = curses.color_pair(4)
    C_GREEN = curses.color_pair(3)
    C_RED = curses.color_pair(2)

    # test dash-cli in path -- TODO make robust
    try:
        run_command('dash-cli getinfo')
    except subprocess.CalledProcessError:
        quit(
            "--> cannot find dash-cli in $PATH\n" +
            "    do: export PATH=/path/to/dash-cli-folder:$PATH\n" +
            "    and try again\n")

    # get ballot
    ballot = json.loads(run_command('dash-cli mnbudget show'))
    for entry in ballot:
        ballot[entry][u'vote'] = 'ABSTAIN'
    ballot_entries = sorted(ballot, key=lambda s: s.lower())
    votecount = len(ballot_entries)
    max_proposal_len = 0
    for entry in ballot_entries:
        max_proposal_len = max(max_proposal_len, len(entry))

    # extract mnprivkey,txid-txidx from masternode.conf
    masternodes = {}
    with open(os.path.join(dash_conf_dir, 'masternode.conf'), 'r') as f:
        lines = list(
            line
            for line in
            (l.strip() for l in f)
            if line and not line.startswith('#'))
        for line in lines:
            conf = line.split()
            masternodes[
                conf[0]] = {
                "mnprivkey": conf[2],
                "fundtx": conf[3] +
                '-' +
                conf[4],
                "txid": conf[3],
                "txout": conf[4]}
    if not masternodes:
        # fallback to dash.conf entries if no masternode.conf entries
        with open(os.path.join(dash_conf_dir, 'dash.conf'), 'r') as f:
            lines = list(
                line
                for line in
                (l.strip() for l in f)
                if line and not line.startswith('#'))
            conf = {}
            for line in lines:
                n, v = line.split('=')
                conf[n.strip(' ')] = v.strip(' ')
            conf['masternodeaddr'] = re.sub('[\[\]]', '', conf['masternodeaddr'])
            if all(k in conf for k in ('masternode', 'masternodeaddr', 'masternodeprivkey')):
                # get funding tx from dashninja
                import urllib2
                mninfo = urllib2.urlopen(
                    "https://dashninja.pl/api/masternodes?ips=[\"" +
                    conf['masternodeaddr'] +
                    "\"]&portcheck=1").read()
                try:
                    mndata = json.loads(mninfo)
                except:
                    quit('cannot retrieve masternode info from dashninja')
                d = mndata[u'data'][0]
                vin = str(d[u'MasternodeOutputHash'])
                vidx = str(d[u'MasternodeOutputIndex'])
                masternodes[conf['masternodeaddr']] = {
                    "mnprivkey": conf['masternodeprivkey'],
                    "fundtx": vin +
                    '-' +
                    vidx,
                    "txid": vin,
                    "txout": vidx}
            else:
                quit('cannot find masternode information in dash.conf')

    # TODO open previous votes/local storage something

    votewin = curses.newwin(votecount +
                            8, max(max_proposal_len +
                                   len(str(len(masternodes))) +
                                   28, 49), 1, 2)
    votewin.keypad(1)
    votewin.border()

    votewin.addstr(1, 2, 'dashvote version: ' + VERSION, C_CYAN)
    votewin.addstr(
        2,
        2,
        'use arrow keys to set votes for %s masternodes' %
        len(masternodes),
        C_YELLOW)
    votewin.addstr(3, 2, 'hit enter on CONFIRM to vote', C_YELLOW)
    _y = 4
    for entry in ballot_entries:
        _y += 1
        votewin.addstr(_y, 4, entry, C_CYAN)
        votewin.addstr(
            _y,
            max_proposal_len +
            6,
            'ABSTAIN',
            C_YELLOW)
    votewin.addstr(
        _y + 2,
        max_proposal_len + 6,
        'confirm',
        C_YELLOW)
    votewin.move(0 + 5, max_proposal_len + 6)

    votewin.refresh()

    keys = {
        curses.KEY_UP: lambda s: prev_vote(s),
        curses.KEY_DOWN: lambda s: next_vote(s),
        curses.KEY_RIGHT: lambda s: set_vote(ballot, s, 1),
        curses.KEY_LEFT: lambda s: set_vote(ballot, s, -1),
        10: lambda s: submit_votes(stdscr, ballot, s)
    }

    sel_vote = 0
    while True:
        key = votewin.getch()
        f = keys.get(key, lambda s: 'not mapped')
        sel_vote = f(sel_vote)
        try:
            entry_vote = ballot[ballot_entries[sel_vote]][u'vote']
        except IndexError:
            # CONFIRM button
            entry_vote = ''
        if key != 10:
            update_vote_display(votewin, sel_vote, entry_vote)


if __name__ == '__main__':
    curses.wrapper(main)
