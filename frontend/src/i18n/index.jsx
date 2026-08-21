// i18n — Bengali/English localisation.
//
// Bengali is table stakes in the Bangladesh ISP market (NetFee and ISP
// Digital both ship Bangla; support is expected in Bangla too). The
// language choice is per-user and persisted locally so it survives
// offline use — it is UI preference, not business data, so localStorage
// is appropriate here.
//
// Numerals: Bengali uses ০-৯. Money and counts are converted at render
// time so tables stay aligned (tabular-nums works for both scripts).

import { createContext, useContext, useEffect, useState } from "react";
import { en } from "./en";
import { bn } from "./bn";

const DICTS = { en, bn };
const I18nContext = createContext(null);

const BN_DIGITS = ["০", "১", "২", "৩", "৪", "৫", "৬", "৭", "৮", "৯"];

export function toBengaliDigits(value) {
  return String(value).replace(/\d/g, (d) => BN_DIGITS[Number(d)]);
}

export function I18nProvider({ children }) {
  const [lang, setLang] = useState(() => localStorage.getItem("arq_lang") || "bn");

  useEffect(() => {
    localStorage.setItem("arq_lang", lang);
    document.documentElement.lang = lang;
  }, [lang]);

  const dict = DICTS[lang] || DICTS.en;

  /** t("customers.title") with {placeholder} interpolation and safe
   *  fallback to English, then to the key itself, so a missing string is
   *  visible in QA rather than rendering blank. */
  const t = (key, vars) => {
    let s = dict[key] ?? DICTS.en[key] ?? key;
    if (vars) for (const [k, v] of Object.entries(vars)) s = s.replaceAll(`{${k}}`, v);
    return s;
  };

  /** Locale-aware number: Bengali numerals when lang === 'bn'. */
  const n = (value) => {
    const formatted = Number(value || 0).toLocaleString("en-US");
    return lang === "bn" ? toBengaliDigits(formatted) : formatted;
  };

  /** Money with the Taka sign, locale numerals. */
  const money = (value) => `৳ ${n(value)}`;

  return (
    <I18nContext.Provider value={{ lang, setLang, t, n, money }}>
      {children}
    </I18nContext.Provider>
  );
}

export function useI18n() {
  const ctx = useContext(I18nContext);
  // Fail soft: components must still render if used outside the provider
  // (e.g. the login screen before providers mount).
  if (!ctx) {
    return {
      lang: "en", setLang: () => {},
      t: (k) => en[k] ?? k,
      n: (v) => Number(v || 0).toLocaleString("en-US"),
      money: (v) => `৳ ${Number(v || 0).toLocaleString("en-US")}`,
    };
  }
  return ctx;
}

/** Language switcher used in the top bar. */
export function LanguageToggle() {
  const { lang, setLang } = useI18n();
  return (
    <button
      className="btn btn-ghost"
      style={{ padding: "6px 10px", fontSize: 12, fontWeight: 700 }}
      onClick={() => setLang(lang === "bn" ? "en" : "bn")}
      aria-label={lang === "bn" ? "Switch to English" : "বাংলায় পরিবর্তন করুন"}
      title={lang === "bn" ? "Switch to English" : "বাংলায় দেখুন"}
    >
      {lang === "bn" ? "EN" : "বাং"}
    </button>
  );
}
