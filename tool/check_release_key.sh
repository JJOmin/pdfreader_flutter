#!/bin/sh
# Checks that a release keystore opens with the password, alias and key password it will be built with,
# and says which one is wrong, in seconds: a wrong one otherwise shows only at the end of a long build.
# Reads KEYSTORE (a file), STORE_PASSWORD, KEY_ALIAS and KEY_PASSWORD from the environment. Used by
# .github/workflows/release.yml; try it here with the values of android/key.properties.
set -u
fail() { echo "::error::$1"; exit 1; }

[ -f "${KEYSTORE:-}" ] || fail "There is no keystore file. Is ANDROID_KEYSTORE_BASE64 set, and is it the whole base64 text of release.jks?"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1. The keystore opens with the store password, and holds a key.
if ! keytool -list -keystore "$KEYSTORE" -storepass "$STORE_PASSWORD" >"$tmp/list" 2>"$tmp/err"; then
  fail "The keystore does not open: ANDROID_KEYSTORE_PASSWORD is wrong (or has a stray space or line break), or ANDROID_KEYSTORE_BASE64 is not a keystore ($(head -c 160 "$tmp/err" | tr '\n' ' '))."
fi
aliases=$(grep -E 'PrivateKeyEntry' "$tmp/list" | cut -d, -f1 | tr '\n' ' ')
[ -n "$aliases" ] || fail "The keystore opens but holds no private key."

# 2. The alias is one of them. (An alias is a name, not a secret.)
case " $aliases" in
  *" $KEY_ALIAS "*) ;;
  *) fail "ANDROID_KEY_ALIAS is '$KEY_ALIAS', but the keystore holds: $aliases" ;;
esac

# 3. The key password opens that key. A PKCS12 keystore (what keytool makes today) has one password for
#    the keystore and its keys: a key password that differs fails only when the app is signed.
if grep -q "Keystore type: PKCS12" "$tmp/list"; then
  [ "$KEY_PASSWORD" = "$STORE_PASSWORD" ] ||
    fail "ANDROID_KEY_PASSWORD must be the same as ANDROID_KEYSTORE_PASSWORD: this keystore is PKCS12, which has one password for both."
else
  # An older (JKS) keystore can have its own key password: copying the key out reads it with that.
  keytool -importkeystore -noprompt -srckeystore "$KEYSTORE" -srcstorepass "$STORE_PASSWORD" \
      -srcalias "$KEY_ALIAS" -srckeypass "$KEY_PASSWORD" -destkeystore "$tmp/copy.p12" \
      -deststoretype PKCS12 -deststorepass copy-check >"$tmp/out" 2>&1 ||
    fail "ANDROID_KEY_PASSWORD does not open the key '$KEY_ALIAS'."
fi
echo "The release key '$KEY_ALIAS' opens with these passwords."
