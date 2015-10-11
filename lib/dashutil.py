import base64
import hashlib


import ecdsa
import utils

import sys
import os
sys.path.append(os.path.dirname(os.path.abspath(__file__)) + '/pycoin')
from pycoin.key import Key
from pycoin.ecdsa import generator_secp256k1
from pycoin.ecdsa import ellipticcurve, numbertheory


class Bip62SigningKey(ecdsa.SigningKey):
    """Enforce low S values in signatures"""

    def sign_number(self, number, entropy=None, k=None):
        curve = ecdsa.SECP256k1
        G = curve.generator
        order = G.order()
        r, s = ecdsa.SigningKey.sign_number(self, number, entropy, k)
        if s > order/2:
            s = order - s
        return r, s


def str_to_long(b):
    res = 0
    pos = 1
    for a in reversed(b):
        res += ord(a) * pos
        pos *= 256
    return res


def sign_vote(votestr, mnprivkey):
    privatekey = utils.wifToPrivateKey(mnprivkey)
    signingkey = Bip62SigningKey.from_string(privatekey.decode('hex'), curve=ecdsa.SECP256k1)
    public_key = signingkey.get_verifying_key()
    key = Key.from_text(mnprivkey)
    address = key.address(use_uncompressed=True)
    msghash = utils.double_sha256(utils.msg_magic(votestr))
    signature = signingkey.sign_digest_deterministic(msghash, hashfunc=hashlib.sha256, sigencode=ecdsa.util.sigencode_string)
    assert public_key.verify_digest(signature, msghash, sigdecode=ecdsa.util.sigdecode_string)
    for i in range(4):
        sig = base64.b64encode(chr(27+i) + signature)
        if verify_bitcoin_signature(generator_secp256k1, address, msghash, sig):
            return sig


def verify_bitcoin_signature(generator, address, message, signature):
#    compressed = False
    G = generator
    curve = G.curve()
    order = G.order()
    _a, _b, _p = curve.a(), curve.b(), curve.p()
    sig = base64.b64decode(signature)
    if len(sig) != 65:
        raise Exception("vmB", "Bad signature")

    hb = ord(sig[0])
    r, s = map(str_to_long, [sig[1:33], sig[33:65]])

    if hb < 27 or hb >= 35:
        raise Exception("vmB", "Bad first byte")
    if hb >= 31:
#        compressed = True
        hb -= 4

    recid = hb - 27
    x = (r + (recid/2) * order) % _p
    y2 = (pow(x, 3, _p) + _a*x + _b) % _p
    yomy = numbertheory.modular_sqrt(y2, _p)
    if (yomy - recid) % 2 == 0:
        y = yomy
    else:
        y = _p - yomy
    R = ellipticcurve.Point(curve, x, y, order)
    e = str_to_long(message)
    minus_e = -e % order
    inv_r = numbertheory.inverse_mod(r, order)
    Q = inv_r * (R * s + G * minus_e)
    key = Key(public_pair=(Q.x(), Q.y()), netcode='DASH')
    return key.address(use_uncompressed=True) == address
