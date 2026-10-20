package com.jerry.attest;

import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;
import java.security.spec.ECGenParameterSpec;

/**
 * Prints the verifiedBootHash (64 hex chars) that the TEE attests in a fresh
 * key-attestation certificate. Run: CLASSPATH=attest.dex app_process / com.jerry.attest.Main
 * Prints nothing and exits 1 on failure.
 */
public class Main {
    private static final String ALIAS = "jerry_attest_probe";
    private static final String KEY_DESC_OID = "1.3.6.1.4.1.11129.2.1.17";
    private static final int TAG_ROOT_OF_TRUST = 704;

    public static void main(String[] args) {
        KeyStore ks = null;
        try {
            ensureKeyStoreProvider();
            ks = KeyStore.getInstance("AndroidKeyStore");
            ks.load(null);
            if (ks.containsAlias(ALIAS)) ks.deleteEntry(ALIAS);

            KeyPairGenerator kpg = KeyPairGenerator.getInstance(
                    KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore");
            kpg.initialize(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
                    .setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1"))
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .setAttestationChallenge(new byte[]{1, 2, 3, 4, 5, 6, 7, 8})
                    .build());
            kpg.generateKeyPair();

            Certificate[] chain = ks.getCertificateChain(ALIAS);
            if (chain == null || chain.length == 0) fail("no chain");
            byte[] ext = ((X509Certificate) chain[0]).getExtensionValue(KEY_DESC_OID);
            if (ext == null) fail("no attestation extension");

            byte[] hash = findVerifiedBootHash(ext);
            if (hash == null || hash.length != 32) fail("no verifiedBootHash");

            StringBuilder sb = new StringBuilder(64);
            for (byte b : hash) sb.append(String.format("%02x", b & 0xff));
            System.out.println(sb);
        } catch (Throwable t) {
            System.err.println("probe error: " + t);
            exit1();
        } finally {
            try { if (ks != null && ks.containsAlias(ALIAS)) ks.deleteEntry(ALIAS); }
            catch (Throwable ignored) { }
        }
    }

    /**
     * A bare app_process (no Zygote app init) has no "AndroidKeyStore" security
     * provider registered. Register it via the hidden provider class.
     */
    private static void ensureKeyStoreProvider() {
        try { android.os.Looper.prepareMainLooper(); } catch (Throwable ignored) { }

        if (java.security.Security.getProvider("AndroidKeyStore") != null) return;

        String[] classes = {
                "android.security.keystore2.AndroidKeyStoreProvider",  // Android 12+
                "android.security.keystore.AndroidKeyStoreProvider"    // older
        };
        for (String cn : classes) {
            try {
                Class<?> c = Class.forName(cn);
                try {
                    c.getDeclaredMethod("install").invoke(null);
                } catch (Throwable viaInstall) {
                    java.lang.reflect.Constructor<?> k = c.getDeclaredConstructor();
                    k.setAccessible(true);
                    java.security.Security.addProvider((java.security.Provider) k.newInstance());
                }
                if (java.security.Security.getProvider("AndroidKeyStore") != null) return;
            } catch (Throwable ignored) { }
        }
    }

    private static void fail(String m) { System.err.println("probe: " + m); exit1(); }
    private static void exit1() { System.exit(1); }

    // ---- minimal DER reader ----
    private static final class Tlv {
        int cls;        // 0 universal, 1 app, 2 context, 3 private
        boolean cons;
        int tag;
        int start;      // content start
        int end;        // content end (exclusive)
    }

    private static Tlv read(byte[] d, int pos, int limit) {
        if (pos >= limit) return null;
        Tlv t = new Tlv();
        int b = d[pos++] & 0xff;
        t.cls = b >> 6;
        t.cons = (b & 0x20) != 0;
        int tag = b & 0x1f;
        if (tag == 0x1f) {
            tag = 0;
            int x;
            do {
                if (pos >= limit) return null;
                x = d[pos++] & 0xff;
                tag = (tag << 7) | (x & 0x7f);
            } while ((x & 0x80) != 0);
        }
        t.tag = tag;
        if (pos >= limit) return null;
        int len = d[pos++] & 0xff;
        if ((len & 0x80) != 0) {
            int n = len & 0x7f;
            if (n == 0 || n > 4 || pos + n > limit) return null;
            len = 0;
            for (int i = 0; i < n; i++) len = (len << 8) | (d[pos++] & 0xff);
        }
        if (len < 0 || pos + len > limit) return null;
        t.start = pos;
        t.end = pos + len;
        return t;
    }

    private static byte[] findVerifiedBootHash(byte[] extValue) {
        // extValue = OCTET STRING { KeyDescription SEQUENCE }
        Tlv oct = read(extValue, 0, extValue.length);
        if (oct == null) return null;
        Tlv seq = read(extValue, oct.start, oct.end);
        if (seq == null) return null;

        // KeyDescription: [0]ver [1]attSecLvl [2]kmVer [3]kmSecLvl [4]challenge [5]uniqueId
        //                 [6]softwareEnforced [7]teeEnforced
        int idx = 0, p = seq.start;
        byte[] found = null;
        while (p < seq.end) {
            Tlv c = read(extValue, p, seq.end);
            if (c == null) break;
            if (idx >= 6 && c.cons) {            // the two AuthorizationLists
                byte[] h = rootOfTrustHash(extValue, c);
                if (h != null) found = h;        // prefer teeEnforced (later one)
            }
            p = c.end;
            idx++;
        }
        return found;
    }

    private static byte[] rootOfTrustHash(byte[] d, Tlv authList) {
        int p = authList.start;
        while (p < authList.end) {
            Tlv f = read(d, p, authList.end);
            if (f == null) return null;
            if (f.cls == 2 && f.tag == TAG_ROOT_OF_TRUST) {
                Tlv rot = read(d, f.start, f.end);   // explicit tag -> SEQUENCE
                if (rot == null) return null;
                // RootOfTrust: key OCTET STRING, locked BOOLEAN, state ENUM, hash OCTET STRING
                int q = rot.start, i = 0;
                while (q < rot.end) {
                    Tlv e = read(d, q, rot.end);
                    if (e == null) return null;
                    if (i == 3 && e.tag == 4) {
                        byte[] out = new byte[e.end - e.start];
                        System.arraycopy(d, e.start, out, 0, out.length);
                        return out;
                    }
                    q = e.end;
                    i++;
                }
                return null;
            }
            p = f.end;
        }
        return null;
    }
}
