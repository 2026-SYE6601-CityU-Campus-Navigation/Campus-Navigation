/**
 * 采样点里那条 WiFi 摘要的生成与解析（`bssid:rssi;bssid:rssi;…`）。
 *
 * ⚠️ 2026-09-30（第二十九轮）单独抽成模块的原因：**「取哪几个 AP」这件事正是指纹能不能用的关键**，
 * 而它原来嵌在 `TrackRecorder.refreshWifi()` 里（要真机 + 传感器才跑得起来，离线测不了）。
 *
 * 为什么必须多留、且排序必须确定（实测证据，独树阳光里两条同路线轨迹）：
 *  - 同一个地方、**相隔 30 秒**的两次扫描，原来「最强的 5 个」重合 **0 个**；
 *  - 现场可见 AP 有 150~200 个，最强的那些 RSSI 挤在 8~10 dB 内又是整数 → 大量并列；
 *  - 于是「前 5 名」等于在并列池里随机抓 5 个，同地点指纹重合度中位数是 **0**（异地也有 0.003）。
 * 现在改成按 (rssi 降序, bssid 升序) 取前 40 —— **bssid 兜底不能省**，
 * 没有它并列项的相对顺序每次都不一样，多留多少个都白搭。
 */

export interface ApSample {
  bssid: string;
  rssi: number;
}

/**
 * 按 (rssi 降序, bssid 升序) 确定地取前 `keep` 个，拼成摘要串。
 * 输入用两个平行数组而不是对象数组：ArkTS 是**名义类型**，
 * `wifiManager.WifiScanInfo[]` 不能直接当 `ApSample[]` 传（会报 arkts-no-structural-typing）。
 */
export function wifiSummary(bssids: string[], rssis: number[], keep: number): string {
  const n: number = Math.min(bssids.length, rssis.length);
  const idx: number[] = [];
  for (let i = 0; i < n; i++) {
    idx.push(i);
  }
  idx.sort((a: number, b: number): number => {
    if (rssis[a] !== rssis[b]) {
      return rssis[b] - rssis[a];
    }
    if (bssids[a] === bssids[b]) {
      return 0;
    }
    return bssids[a] < bssids[b] ? -1 : 1;
  });
  const take: number = keep < idx.length ? keep : idx.length;
  const parts: string[] = [];
  for (let i = 0; i < take; i++) {
    const k: number = idx[i];
    parts.push(`${bssids[k]}:${rssis[k]}`);
  }
  return parts.join(';');
}

/**
 * 解析摘要串。BSSID 自身含 5 个冒号，所以每条是「6 段地址 + 1 段 rssi」——
 * 老数据（只留 5 个）与 2026-09-30 之后的数据（留 40 个）格式相同，都能解析。
 */
export function parseWifiSummary(s: string): ApSample[] {
  const out: ApSample[] = [];
  if (s.length === 0) {
    return out;
  }
  for (const kv of s.split(';')) {
    const a: string[] = kv.split(':');
    if (a.length < 7) {
      continue;
    }
    const rssi: number = Number.parseFloat(a[6]);
    if (Number.isNaN(rssi)) {
      continue;
    }
    out.push({ bssid: a.slice(0, 6).join(':'), rssi: rssi });
  }
  return out;
}
