import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

/**
 * 权限的「申请 — 判断 — 补授」这一套（2026-10-06 新增）。
 *
 * **为什么要有这个模块**：2026-10-05 用户带机去城大采集，新版本全程没有 GPS，
 * 排查下来是**位置权限根本没给**（包名改成 hk.edu.cityu.campusnav 后系统视作新 App，
 * 旧授权不继承），而 App 一声不吭。根因是 `EntryAbility` 里那句
 *
 *     atManager.requestPermissionsFromUser(ctx, [...]).then(() => hilog.info('granted'))
 *
 * —— **`requestPermissionsFromUser` 在用户点「拒绝」时同样是 resolve 的**，真正的结果在
 * 返回值的 `authResults` 数组里（0 = 允许，-1 = 拒绝），只有 API 层自己出错才 reject。
 * 所以那句 `.then` 是**无条件**打「granted」，拒绝与批准写出一模一样的日志 —— 代码在撒谎，
 * 用户在手机上也就不可能看出来。**教训：拿到 Promise 的 resolve 不等于拿到权限。**
 *
 * 本模块把三件事收在一处：
 *  ① 纯函数（可离线单测）：从 authResults 算「缺哪几项」、把权限名翻成人话；
 *  ② `requestAndReport()`：申请并**如实**返回缺失项（供 EntryAbility 落进 AppStorage）；
 *  ③ `queryMissing()`：**静默**查询当前状态（不弹窗）—— 用户去系统设置里开完权限回来，
 *     首页靠它把提示条自己收掉；以及 `openSettingsForMissing()`：把拒绝过的用户送去设置页
 *     （连续拒绝两次后系统不再弹窗，设置页是唯一的出路）。
 *
 * ⚠️ 只有本文件 import `Permissions`（SDK 的字符串字面量联合类型）。ArkTS 是**名义类型**，
 * `string` 不能当 `Permissions` 用 —— 所以权限清单必须声明成 `Permissions[]`，
 * 页面只传 `string[]`，转换收在这里。若哪天报 `Permissions` 找不到，就在
 * `@ohos.abilityAccessCtrl` 里找同名类型替换 import。
 */

const TAG = 'RoomMarker';

/**
 * 本 App 需要的**用户授权**权限。这个数组的顺序同时是：
 *  ① `requestPermissionsFromUser` 的请求顺序；② 它的 `permissions`/`authResults` 返回顺序。
 * 所以增删项只改这一处，别在调用点再抄一份（本工程吃过「两张表只改一张」的亏）。
 */
export const NEEDED_PERMISSIONS: Permissions[] = [
  'ohos.permission.LOCATION',
  'ohos.permission.APPROXIMATELY_LOCATION',
  'ohos.permission.LOCATION_IN_BACKGROUND',
  'ohos.permission.ACCELEROMETER',
  'ohos.permission.GYROSCOPE',
  'ohos.permission.ACTIVITY_MOTION'
];

/** 与定位有关的几项（消息里要单独说清后果） */
const LOCATION_PERMS: string[] = [
  'ohos.permission.LOCATION',
  'ohos.permission.APPROXIMATELY_LOCATION'
];

/** `authResults` 里「已授权」的值（`abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED`） */
const GRANTED = 0;

/** AppStorage 键：还缺哪几项权限（`string[]`；空数组 = 都拿到了） */
export const PERM_MISSING_KEY = 'rm_perm_missing';

/**
 * 从 `requestPermissionsFromUser` 的返回值里算出**被拒**的那些权限名。纯函数，可离线单测。
 *
 * 注意两点：① 判据是 `authResults[i] !== 0`，**不是** Promise 有没有 reject；
 * ② `authResults` 与 `permissions` 一一对应，但长度不一时**短的那侧按「拒绝」处理**
 * （宁可多提示一次，也不要把没拿到的权限当成拿到了）。
 */
export function missingFromResults(perms: string[], authResults: number[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < perms.length; i++) {
    const r: number = i < authResults.length ? authResults[i] : -1;
    if (r !== GRANTED) {
      out.push(perms[i]);
    }
  }
  return out;
}

/** 权限名 → 用户看得懂的名字。纯函数。认不出的原样返回（便于以后加权限时不会显示成空白）。 */
export function permissionLabel(p: string): string {
  if (p === 'ohos.permission.LOCATION') {
    return '位置信息';
  }
  if (p === 'ohos.permission.APPROXIMATELY_LOCATION') {
    return '大致位置';
  }
  if (p === 'ohos.permission.LOCATION_IN_BACKGROUND') {
    return '后台定位（要选「始终允许」）';
  }
  if (p === 'ohos.permission.ACCELEROMETER') {
    return '加速度计';
  }
  if (p === 'ohos.permission.GYROSCOPE') {
    return '陀螺仪';
  }
  if (p === 'ohos.permission.ACTIVITY_MOTION') {
    return '运动与健身';
  }
  return p;
}

/** 缺失项的名字列表，顿号分隔。纯函数。 */
export function permissionLabels(missing: string[]): string {
  const names: string[] = [];
  for (const p of missing) {
    names.push(permissionLabel(p));
  }
  return names.join('、');
}

/** 提示条标题。纯函数。 */
export function permissionTitle(missing: string[]): string {
  return missing.length === 0 ? '' : `还有 ${missing.length} 项权限没打开`;
}

/**
 * 「缺了会怎样」的那句话。纯函数。
 *
 * 刻意把**后果**写出来而不是只说「请授权」：上一轮就是因为在手机上完全看不到后果，
 * 白跑了一趟采集。`LOCATION_IN_BACKGROUND` 单独一句 —— 它只影响**退到后台/熄屏**，
 * 采集时手机常在口袋里，这一项掉了会让「录到一半 GPS 没了」，且现场看不出来。
 */
export function describeMissing(missing: string[]): string {
  if (missing.length === 0) {
    return '';
  }
  const parts: string[] = [];
  if (missing.indexOf(LOCATION_PERMS[0]) >= 0 || missing.indexOf(LOCATION_PERMS[1]) >= 0) {
    parts.push('轨迹里不会记录 GPS 点，室内推算也没有锚点可用');
  }
  if (missing.indexOf('ohos.permission.LOCATION_IN_BACKGROUND') >= 0) {
    parts.push('退到后台或熄屏后定位会被系统暂停，采集时手机装在口袋里会「录到一半就没有位置了」');
  }
  if (missing.indexOf('ohos.permission.ACCELEROMETER') >= 0
    || missing.indexOf('ohos.permission.GYROSCOPE') >= 0) {
    parts.push('步态与朝向推算收不到原始数据');
  }
  if (missing.indexOf('ohos.permission.ACTIVITY_MOTION') >= 0) {
    parts.push('系统计步不可用');
  }
  const why: string = parts.length > 0 ? `会导致：${parts.join('；')}。` : '';
  return `缺少「${permissionLabels(missing)}」授权。${why}请在系统设置里打开后再回来采集。`;
}

/**
 * 申请权限并**如实**返回还缺哪几项。
 *
 * ⚠️ 调用方必须用返回值，**不要因为 Promise 成功就以为拿到了**（这是本模块存在的理由）。
 * 请求本身抛错（参数非法、权限名无效等）时，按「一项都没拿到」处理 —— 这是诚实的方向。
 */
export async function requestAndReport(context: common.UIAbilityContext): Promise<string[]> {
  const at: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
  try {
    // 不写显式类型注解：返回值类型由 SDK 推断，免得手写类型名写错反而编译不过
    const res = await at.requestPermissionsFromUser(context, NEEDED_PERMISSIONS);
    const missing: string[] = missingFromResults(res.permissions, res.authResults);
    hilog.info(0x0000, TAG, '权限申请完成：共 %{public}d 项，缺 %{public}d 项 %{public}s',
      res.permissions.length, missing.length, JSON.stringify(missing));
    return missing;
  } catch (e) {
    hilog.error(0x0000, TAG, '权限申请失败（按全缺处理）：%{public}s', JSON.stringify(e));
    const all: string[] = [];
    for (const p of NEEDED_PERMISSIONS) {
      all.push(p);
    }
    return all;
  }
}

/**
 * **静默**查询当前还缺哪几项（不弹窗）。
 *
 * 返回 `undefined` = **查不出来**（拿不到自己的 tokenId 等），调用方应保留原值、
 * 不要当成「都不缺」—— 宁可留着上一次的真实结果，也不要因为查询失败把提示条误收掉。
 */
export function queryMissing(): string[] | undefined {
  let tokenId = -1;
  try {
    const info = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    tokenId = info.appInfo.accessTokenId;
  } catch (e) {
    hilog.warn(0x0000, TAG, '查不到自身 tokenId，跳过权限自查：%{public}s', JSON.stringify(e));
    return undefined;
  }
  const at: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
  const out: string[] = [];
  for (const p of NEEDED_PERMISSIONS) {
    try {
      const st: abilityAccessCtrl.GrantStatus = at.checkAccessTokenSync(tokenId, p);
      if (st !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        out.push(p);
      }
    } catch (e) {
      out.push(p);
    }
  }
  return out;
}

/**
 * 把用户送去系统设置里的对应权限页。
 *
 * 场景：用户已经拒绝过（连续拒绝两次后系统不再弹窗，`requestPermissionsFromUser` 直接回 -1），
 * 这时**只能**靠设置页。入参用 `string[]`（页面不用 import SDK 的 `Permissions`），
 * 转换在这里做 —— `filter` 的返回类型仍是 `Permissions[]`，不需要强制转换。
 */
export async function openSettingsForMissing(context: common.UIAbilityContext, missing: string[]): Promise<void> {
  const ask: Permissions[] = NEEDED_PERMISSIONS.filter((p: Permissions) => missing.indexOf(p) >= 0);
  if (ask.length === 0) {
    return;
  }
  try {
    const at: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    await at.requestPermissionOnSetting(context, ask);
  } catch (e) {
    hilog.error(0x0000, TAG, '打开权限设置页失败：%{public}s', JSON.stringify(e));
  }
}
