#!/usr/bin/env python

import atexit
import curses
import datetime
import json
import os
import random
import re
import subprocess
import sys
import tempfile
import termios
import time
import tty


VERSION = '0.0.7'
git_dir = os.path.abspath(
    os.path.join(
        os.path.dirname(
            os.path.abspath(__file__)),
        '..'))
dash_conf_dir = os.path.join(os.getenv('HOME'), '.dashcore')
dash_cli_path = os.getenv('DASH_CLI')
if os.getenv('DASHMAN_PID') is None:
    quit("--> please run using 'dashman vote'")

sys.path.append(git_dir + '/lib')
import dashutil


urnd = random.SystemRandom()


def getch():
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        ch = sys.stdin.read(1)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
    return ch

def urandom_int():
    urandom = map(ord, os.urandom(4))
    offset = 0
    for d in range(4):
        offset += pow(urandom[d], 2**d)
    return offset

def random_offset(size):
    bigint = urandom_int()
    offset_range = bigint % size
    return offset_range - (size/2)

def random_timestamp():
    now_epoch = int(time.time())
    urandom = map(ord, os.urandom(4))
    offset = 0
    for d in range(4):
        offset += pow(urandom[d], 2**d)
    return now_epoch - (offset % 86400)


# python <2.7 monkey patch
if "check_output" not in dir( subprocess ):
    def f(*popenargs, **kwargs):
        if 'stdout' in kwargs:
            raise ValueError('stdout argument not allowed, it will be overridden.')
        process = subprocess.Popen(stdout=subprocess.PIPE, *popenargs, **kwargs)
        output, unused_err = process.communicate()
        retcode = process.poll()
        if retcode:
            cmd = kwargs.get("args")
            if cmd is None:
                cmd = popenargs[0]
            raise subprocess.CalledProcessError(retcode, cmd)
        return output
    subprocess.check_output = f

def run_command(cmd):
    return subprocess.check_output(cmd, shell=True)

def run_dash_cli_command(cmd):
    return run_command("%s %s" % (dash_cli_path or 'dash-cli', cmd))

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
    votes = ['NO', 'SKIP', 'YES', 'ABSTAIN']
    vote_idx = {'NO': 0, 'SKIP': 1, 'YES': 2, 'ABSTAIN': 3}
    cur_vote = b[ballot_entries[s]][u'vote']
    b[ballot_entries[s]][u'vote'] = votes[
        (vote_idx[cur_vote] + dir) % len(votes)]
    return s


def update_vote_display(win, sel_ent, vote):
    vote_colors = {
        "YES": C_GREEN,
        "NO": C_RED,
        "SKIP": C_CYAN,
        "ABSTAIN": C_YELLOW,
        '': 4
    }
    _y = 7
    _xoff = 12
    if vote == '':
        sel_ent += 1
        win.move(sel_ent + _y, window_width + _xoff)
        win.addstr('       ')
        win.move(sel_ent + _y, window_width + _xoff)
        win.addstr('CONFIRM', C_GREEN)
        win.move(sel_ent + _y, window_width + _xoff)
    else:
        win.move(sel_ent + _y, window_width + _xoff)
        win.addstr('       ')
        win.move(sel_ent + _y, window_width + _xoff)
        win.addstr(vote, vote_colors[vote])
        win.move(sel_ent + _y, window_width + _xoff)


def submit_votes(win, ballot, s):
    if s < votecount:
        return s

    background_send = 0
    if len(masternodes) > 2:
        background_send = 1

    votes_to_send = {}
    for entry in sorted(ballot, key=lambda s: s.lower()):
        if ballot[entry][u'vote'] != 'SKIP':
            votes_to_send[entry] = ballot[entry]

    votewin.clear()
    stdscr.move(0, 0)

    votenum=0
    if votes_to_send.keys():
        if background_send:
            stdscr.addstr("writing time-randomized votes to disk\n\n", C_GREEN)
        else:
            stdscr.addstr("sending time-randomized votes\n\n", C_GREEN)
        stdscr.refresh()

        # spread out over remaining voting duration
        total_sends = (len(votes_to_send) * len(masternodes))
        vote_window = int(86400*(float(days_to_finalization)-0.5))
        randset = urnd.sample(xrange(1,vote_window), len(masternodes) * len(votes_to_send))

        vote_files = []
        shuffled_mn_keys = masternodes.keys()
        urnd.shuffle(shuffled_mn_keys)


        batch_timestamp = datetime.datetime.strftime(datetime.datetime.now(),'%Y%m%d%H%M%S')
        for mn in shuffled_mn_keys:

            offsets = sorted(randset[:len(votes_to_send)])
            del randset[:len(votes_to_send)]
            delays = offsets[:1] + [y-x for x,y in zip(offsets, offsets[1:])]

            if background_send:
                deferred_votes = tempfile.NamedTemporaryFile(prefix=('sending_dashvote_votes-%s=' % batch_timestamp),delete=False)
                deferred_votes.write("#!/bin/bash\n")
                deferred_votes.write("set -x\n")
                os.chmod(deferred_votes.name, 0700)
                vote_files.append(deferred_votes)

            shuffled_vote_keys = votes_to_send.keys()
            urnd.shuffle(shuffled_vote_keys)
            for vote in shuffled_vote_keys:
                castvote = str(votes_to_send[vote][u'vote'])
                stdscr.addstr('  ' + vote, C_YELLOW)
                stdscr.addstr(" --> ")
                stdscr.addstr(castvote, castvote == 'YES' and C_GREEN or C_RED)
                stdscr.addstr(" -- ")
                stdscr.addstr(str(votes_to_send[vote][u'Hash']))
                stdscr.addstr("\n")

                votenum += 1
                node = masternodes[mn]
                alias = masternodes[mn]['alias']
                random_ts = random_timestamp()
                ts = datetime.datetime.fromtimestamp(random_ts)
                stdscr.addstr('    ' + alias, C_CYAN)
                stdscr.addstr(' ' + str(ts) + ' ', C_YELLOW)
                netvote = '|'.join([str(node['fundtx']),str(votes_to_send[vote][u'Hash']),"1",
                        str(votes_to_send[vote][u'vote'] == 'YES' and 1 or votes_to_send[vote][u'vote'] == 'NO' and 2 or 3),str(random_ts)])
                mnprivkey = node['mnprivkey']
                signature = dashutil.sign_vote(netvote, mnprivkey)
                command = ('%s' % dash_cli_path is not None and dash_cli_path or 'dash-cli') + ' voteraw ' + str(node['txid']) + ' ' + str(node['txout']) + ' ' + str(
                    votes_to_send[vote][u'Hash']) + ' funding ' + str(votes_to_send[vote][u'vote']).lower() + ' ' + str(random_ts) + ' ' + signature
                if background_send:
                    sleeptime = delays.pop(0)
                    deferred_votes.write("echo \"sleeping %s seconds then casting vote %s/%s\"\n" % (sleeptime,votenum,total_sends))
                    deferred_votes.write("sleep %s\n" % sleeptime)
                    deferred_votes.write("%s\n" % (command))
                    #msg = 'vote successfully created - %s' % sleeptime
                    msg = 'vote successfully created'
                else:
                    try:
                        msg = run_command(command)
                    except subprocess.CalledProcessError,e:
                        msg = 'error running vote command: %s' % command
                stdscr.addstr(
                    msg.rstrip("\n") +
                    "\n",
                    'successfully' in msg and C_GREEN or C_RED)
                stdscr.refresh()

        if background_send:
            voter_parent = tempfile.NamedTemporaryFile(prefix=('sending_dash_votes-%s-' % batch_timestamp), delete=False)
            voter_parent.write("#!/bin/bash\n")
            voter_parent.write('trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT' + "\n")
            os.chmod(voter_parent.name, 0700)
            for deferred_votes in vote_files:
                if deferred_votes.tell() > 1 :
                    deferred_votes.write("rm -- \"$0\"\n")
                    deferred_votes.close()
                    exec_path = deferred_votes.name
                    log_path = exec_path + '.log'
                    voter_parent.write("%s > %s &\n" % (exec_path, log_path ))
            voter_parent.write("wait\n")
            exec_path = voter_parent.name
            voter_parent.close()
            log_path = exec_path + '.log'
            with open(log_path, 'wb') as log:
                p = subprocess.Popen([exec_path],
                                     cwd="/tmp", stdout=log, stderr=log)
            msg = 'sending votes in background'
            stdscr.addstr( "\n" + msg + "\n", C_YELLOW )
            stdscr.refresh()
            msg = 'votes being sent by: %s, pid %s' % ( voter_parent.name, p.pid)
            stdscr.addstr( "\n" + msg + "\n", C_CYAN )
            stdscr.refresh()

    stdscr.addstr("\nHit any key to exit." + "\n", C_GREEN)
    stdscr.refresh()
    stdscr.getch()
    cleanup()
    quit()


def cleanup():
     curses.nocbreak()
     stdscr.keypad(0)
     curses.echo()
     curses.endwin()

atexit.register(cleanup)


def main(screen):

    global stdscr
    global votecount
    global window_width
    global max_yeacount_len
    global max_naycount_len
    global max_percentage_len
    global max_needed_len
    global days_to_finalization
    global ballot_entries
    global votewin
    global masternodes
    global C_YELLOW, C_GREEN, C_RED, C_CYAN

    stdscr = screen
    stdscr.scrollok(1)

    git_describe = run_command(
        'GIT_DIR=%s GIT_WORK_TREE=%s git describe' %
        (git_dir + '/.git', git_dir)).rstrip("\n").split('-')
    try:
        GIT_VERSION = ('-').join((git_describe[i] for i in [1, 2]))
        version = 'v' + VERSION + ' (' + GIT_VERSION + ')'
    except IndexError:
        version = 'v' + VERSION

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

    if dash_cli_path is None:
        # test dash-cli in path -- TODO make robust
        try:
            run_command('dash-cli getblockchaininfo')
        except subprocess.CalledProcessError:
            quit(
                "--> cannot find dash-cli in $PATH\n" +
                "    do: export PATH=/path/to/dash-cli-folder:$PATH\n" +
                "    and try again\n")

    loadwin = curses.newwin(40, 40, 1, 2)

    loadwin.addstr(1, 2, 'dashvote version: ' + version, C_CYAN)

    mncount = int(run_dash_cli_command('masternode count enabled'))
    block_height = int(run_dash_cli_command('getblockcount'))
    blocks_to_next_cycle = (16616 - (block_height % 16616))
    next_cycle_epoch = int(int(time.time()) + (157.5 * blocks_to_next_cycle))
    days_to_next_cycle = blocks_to_next_cycle / 576.0
    days_to_finalization = days_to_next_cycle - 3

    loadwin.addstr(2, 2, '{:0.2f} days remaining to vote'.format(days_to_finalization), C_GREEN)
    loadwin.addstr(3, 2, 'loading votes. please wait...', C_GREEN)
    loadwin.refresh()
    time.sleep(1)

    # get ballot
    ballots = json.loads(run_dash_cli_command('gobject list all'))
    ballot = {}

    for entry in ballots:

        # unescape data string
        ballots[entry]['_data'] = json.loads(ballots[entry][u'DataHex'].decode("hex"))

        (go_type, go_data) = ballots[entry]['_data'][0]
        ballots[entry][go_type] = go_data

        if str(go_type) == 'watchdog':
            continue

        if int(go_data["type"]) == 2:
            continue

        if int(go_data[u'end_epoch']) < int(time.time()):
            continue

        if (ballots[entry][u'NoCount'] - ballots[entry][u'YesCount']) > mncount/10:
            continue

        if int(go_data[u'end_epoch']) < next_cycle_epoch:
            continue

        ballots[entry][u'vote'] = 'SKIP'
        ballots[entry][u'votes'] = json.loads(run_dash_cli_command('gobject getvotes %s' % entry))

        ballot[entry] = ballots[entry]

    votecount = len(ballot)
    max_proposal_len = 0
    max_yeacount_len = 0
    max_naycount_len = 0
    max_percentage_len = 0
    max_needed_len = 0
    for entry in ballot:
        yeas = ballot[entry][u'YesCount']
        nays = ballot[entry][u'NoCount']
        name = ballot[entry]['proposal'][u'name']
        threshold = mncount/10
        percentage = "{0:.1f}".format(
            (float((yeas + nays)) / float(mncount)) * 100)
        votes_needed = (threshold) - (yeas - nays)
        ballot[entry][u'vote_turnout'] = percentage
        ballot[entry][u'total_votes'] = yeas + nays
        ballot[entry][u'votes_needed'] = votes_needed
        ballot[entry][u'vote_threshold'] = (
            yeas + nays) > threshold and True or False
        ballot[entry][u'vote_passing'] = (
            yeas - nays) > threshold and True or False
        ballot[entry][u'voted_down'] = (
            nays - yeas) > threshold and True or False
        max_proposal_len = max(
            max_proposal_len,
            len(name))
        max_needed_len = max(max_needed_len, len(str(votes_needed)))
        max_yeacount_len = max(max_yeacount_len, len(str(yeas)))
        max_naycount_len = max(max_naycount_len, len(str(nays)))
        max_percentage_len = max(max_percentage_len, len(str(percentage)))

    ballot_entries = sorted(ballot, key=lambda s: ballot[s]['votes_needed'], reverse=False)

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
            masternodes[conf[3] + '-' + conf[4]] = {
                "alias": conf[0],
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
            if all(k in conf for k in ('masternode', 'externalip', 'masternodeprivkey')):
                # get funding tx from dashninja
                import urllib2
                mninfo = urllib2.urlopen(
                    "https://dashninja.pl/api/masternodes?ips=[\"" +
                    conf['externalip'] + ":9999" +
                    "\"]&portcheck=1").read()
                try:
                    mndata = json.loads(mninfo)
                    d = mndata[u'data'][0]
                except:
                    quit('cannot retrieve masternode info from dashninja')
                vin = str(d[u'MasternodeOutputHash'])
                vidx = str(d[u'MasternodeOutputIndex'])
                masternodes[vin + '-' + vidx] = {
                    "alias": conf['externalip'],
                    "mnprivkey": conf['masternodeprivkey'],
                    "fundtx": vin +
                    '-' +
                    vidx,
                    "txid": vin,
                    "txout": vidx}
            else:
                quit('cannot find masternode information in dash.conf')

    # TODO open previous votes/local storage something
    for entry in ballot:
        ballot[entry][u'previously_voted'] = 0
        for hash in ballot[entry][u'votes']:
            b = ballot[entry][u'votes'][hash]
            (vindx,ts,val,mode) = [ b[16:80]+'-'+b[82:83] ] + list(b.split(':')[1:4])
            if vindx in masternodes:
                if val == 'YES':
                    ballot[entry][u'previously_voted'] = 1
                elif val == 'NO':
                    ballot[entry][u'previously_voted'] = 2
                else:
                    ballot[entry][u'previously_voted'] = 3

    loadwin.erase()
    window_width = 35
    content_width = max_proposal_len + max_percentage_len + max_yeacount_len + max_needed_len + max_naycount_len
    window_width = max(window_width, content_width + 3 )
    votewin = curses.newwin(votecount + 10, window_width + 21, 1, 2)
    votewin.keypad(1)
    votewin.border()

    votewin.addstr(1, 2, 'dashvote version: ' + version, C_CYAN)
    votewin.addstr(
        2,
        2,
        'use arrow keys to set votes for {:d} masternodes.  Total nodes: {:d}'.format(len(masternodes), mncount), C_YELLOW)
    votewin.addstr(3, 2, 'hit enter on CONFIRM to vote - q to quit', C_YELLOW)
    votewin.addstr(4, 3, '*', C_GREEN)
    votewin.addstr(4, 4, '/', C_CYAN)
    votewin.addstr(4, 5, '*', C_RED)
    votewin.addstr(4, 7, '== previously voted on proposal (yes/no)', C_YELLOW)
    votewin.addstr(6, 4, 'proposal                                  yeas/nays needs turnout vote', C_CYAN)

    _y = 6
    for entry in ballot_entries:
        _y += 1
        x = 4
        name = ballot[entry]['proposal'][u'name']
        amount = ballot[entry]['proposal'][u'payment_amount']
        yeas = ballot[entry][u'YesCount']
        nays = ballot[entry][u'NoCount']
        percentage = ballot[entry][u'vote_turnout']
        passing = ballot[entry][u'vote_passing']
        threshold = ballot[entry][u'vote_threshold']
        votes_needed = ballot[entry][u'votes_needed']
        if ballot[entry][u'previously_voted'] > 0:
            direction = ballot[entry][u'previously_voted']
            votewin.addstr(_y, x-1, '*', direction == 1 and C_GREEN or C_RED)

        fmt_entry = "%-"+str(max_proposal_len + 2)+"s"
        votewin.addstr(
            _y,
            x,
            fmt_entry % name,
            passing and C_GREEN or threshold and C_RED or C_YELLOW)

        for x in range(max_yeacount_len - len(str(yeas))):
            votewin.addstr(' ')

        votewin.addstr(str(yeas), C_GREEN)
        votewin.addstr('/', C_CYAN)
        votewin.addstr(str(nays), C_RED)

        for x in range(max_naycount_len - len(str(nays))):
            votewin.addstr(' ')

        for x in range(max_needed_len - len(str(votes_needed))):
            votewin.addstr(' ')

        votewin.addstr('   ')
        votewin.addstr(str(votes_needed), C_CYAN)
        votewin.addstr('   ')

        for x in range(max_percentage_len - len(str(percentage))):
            votewin.addstr(' ')

        votewin.addstr(str(percentage) + "%", C_CYAN)

        votewin.addstr(' ')
        votewin.addstr('SKIP', C_CYAN)
    votewin.addstr(
        _y + 2,
        window_width + 12,
        'confirm',
        C_YELLOW)
    votewin.move(0 + 7, window_width + 12)

    votewin.refresh()

    keys = {
        113: lambda s: quit(),
        curses.KEY_UP: lambda s: prev_vote(s),
        curses.KEY_DOWN: lambda s: next_vote(s),
        curses.KEY_RIGHT: lambda s: set_vote(ballot, s, 1),
        curses.KEY_LEFT: lambda s: set_vote(ballot, s, -1),
        107: lambda s: prev_vote(s),
        106: lambda s: next_vote(s),
        108: lambda s: set_vote(ballot, s, 1),
        104: lambda s: set_vote(ballot, s, -1),
        10: lambda s: submit_votes(stdscr, ballot, s)
    }

    sel_vote = 0
    while True:
        key = votewin.getch()
        f = keys.get(key)
        if hasattr(f, '__call__'):
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
