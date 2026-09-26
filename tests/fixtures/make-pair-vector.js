// Makes tests/fixtures/pair-vector.json: one pairing message, the phone's
// key sealed to the PC's RSA key, computed by Node's own crypto module
// (publicEncrypt, RSA-OAEP with SHA-256). It is the reference both sides are
// held to: tests/sections/phone.ps1 decrypts the message with the private
// key given here as .NET's RSAParameters want it, and tests/reply-page-check.js
// seals with docs/reply.html's WebCrypto code and opens that with Node's
// privateDecrypt. OAEP is randomized, so the message itself cannot be
// reproduced - each side proves it by decrypting, not by comparing bytes.
// "code" is the confirmation code of the payload's D, which both sides must
// compute exactly.
//
//     node tests/fixtures/make-pair-vector.js            (keeps the key)
//     node tests/fixtures/make-pair-vector.js --new-key  (a new one)
//
// The RSA key is made once and checked in with the file: a run keeps the key
// already there, so the PowerShell side is not handed a new key each time.
// Run it again only when the wire format changes.
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const out = path.join(__dirname, 'pair-vector.json');
const b64url = (buf) => Buffer.from(buf).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64url = (s) => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');

// .NET's RSAParameters wants every field big-endian at its full width - D as
// long as the modulus, P Q DP DQ InverseQ half that - where a JWK drops
// leading zero bytes; ImportParameters refuses a short one
const fit = (buf, len) => {
    let b = Buffer.from(buf);
    while (b.length > len && b[0] === 0) b = b.subarray(1);
    if (b.length > len) throw new Error('a field longer than ' + len + ' bytes');
    return Buffer.concat([Buffer.alloc(len - b.length), b]);
};

let key;
const old = !process.argv.includes('--new-key') && fs.existsSync(out) ? JSON.parse(fs.readFileSync(out, 'utf8')) : null;
if (old && old.private) {
    const p = old.private;
    const u = (s) => b64url(Buffer.from(s, 'base64'));
    key = crypto.createPrivateKey({
        format: 'jwk',
        key: { kty: 'RSA', n: u(p.Modulus), e: u(p.Exponent), d: u(p.D), p: u(p.P), q: u(p.Q), dp: u(p.DP), dq: u(p.DQ), qi: u(p.InverseQ) }
    });
} else {
    key = crypto.generateKeyPairSync('rsa', { modulusLength: 2048, publicExponent: 65537 }).privateKey;
}
const jwk = key.export({ format: 'jwk' });
const size = unb64url(jwk.n).length;
const half = size / 2;
const std = (s, len) => fit(unb64url(s), len).toString('base64');

const pid = 'abcdefghij';
// fed verbatim, as the page writes it: D is the bytes 0x00..0x1f
const payload = '{"v":2,"d":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8","label":"Android - Chrome 128","ts":1790000000000}';
const D = Buffer.from(Array.from({ length: 32 }, (_, i) => i));
if (b64url(D) !== JSON.parse(payload).d) throw new Error('D is not the payload\'s d');
// the code the phone shows and the user confirms on the PC: the first 4
// bytes of HMAC-SHA256(D, "chatq-confirm") big-endian, mod a million, six
// digits with the leading zeros
const code = String(crypto.createHmac('sha256', D).update(Buffer.from('chatq-confirm', 'utf8')).digest().readUInt32BE(0) % 1000000).padStart(6, '0');
const decrypt = (m) => {
    try {
        return crypto.privateDecrypt({ key, padding: crypto.constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' }, unb64url(m.split('.')[2])).toString('utf8');
    } catch (e) {
        return null;
    }
};
// OAEP is randomized: a message already there that still opens to this
// payload is kept, so a run that only adds a field leaves the rest as it was
let message = old && old.private && old.pid === pid && typeof old.message === 'string' && decrypt(old.message) === payload ? old.message : null;
if (!message) {
    const ct = crypto.publicEncrypt({ key, padding: crypto.constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' }, Buffer.from(payload, 'utf8'));
    message = 'chatq2p.' + pid + '.' + b64url(ct);
}

// what the pair link carries (n and x), and the private half for the PC
const vector = {
    modulus: b64url(fit(unb64url(jwk.n), size)),
    exponent: jwk.e,
    private: {
        Modulus: std(jwk.n, size), Exponent: unb64url(jwk.e).toString('base64'),
        D: std(jwk.d, size), P: std(jwk.p, half), Q: std(jwk.q, half),
        DP: std(jwk.dp, half), DQ: std(jwk.dq, half), InverseQ: std(jwk.qi, half)
    },
    pid,
    payload,
    message,
    code
};
// proved before it is written: Node opens what Node sealed
if (decrypt(message) !== payload) throw new Error('the message does not open');
fs.writeFileSync(out, JSON.stringify(vector, null, 2) + '\n');
console.log((old && old.private ? 'kept the key; ' : 'a new key; ') + (old && message === old.message ? 'kept the message; ' : '') +
    message.length + ' chars: ' + message.slice(0, 40) + '...; code ' + code);
