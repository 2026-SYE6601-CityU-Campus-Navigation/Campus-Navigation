import { CampusBuilding, cityuBuildings } from './Campus';

/**
 * 教室名单：建筑 + 教室代码 + 教室名称，批量建房间用（纯逻辑，便于离线验证）。
 *
 * ⚠️ 数据来源与边界（别把它当成城大官方全量清单）：
 *  - 城大官网 cityu.edu.hk/csc/lt「Lecture Theatre & Classrooms」与 AIMS 的资源预定系统
 *    里的教室总表都需要登录、且对程序访问有反爬（拿到的是机器人拦截页），**抓不到全量清单**。
 *  - 公开资料能查证的是**编号规则**：
 *      · AC1（YEUNG 楊建文學術樓）：教室门漆分红/黄/蓝/绿/紫五色，代码首字母 R/Y/B/G/P；
 *        LT = 講堂，共 18 间，全在 4 樓，不分颜色也不标楼层（单数一侧、偶数一侧）。
 *      · BOC 中國銀行（香港）綜合樓：红色区，代码以 R 开头（资料另点名 LT401）。
 *      · AC2（LI 李達三葉耀珍學術樓）：四位纯数字，首位是楼层，如 1503 = 1 樓 1503。
 *      · AC3（LAU 劉鳴煒學術樓）：楼层-房间号，如 6-213 = 6 樓 213。
 *      · CMC 邵逸夫創意媒體中心：M + 楼层 + 房间号，如 M5001。
 *    来源：城大臺灣學生會「教室地點 Classroom Locations」页、penjc《CityU 手冊》校园地图页
 *    （两处的楼宇简称对照与维基百科「香港城市大學・校園建築」一致）。
 *  - 所以**内置种子只放能逐条查证的部分**（AC1 的 18 间講堂 + BOC LT401），
 *    其余靠「粘贴清单」导入（从 AIMS 课表 / 考试时间表 / 教务处教室表复制过来即可）。
 *    宁可种子少，也不往库里灌伪造的房号。
 */

/** 一行教室：建筑（区域）+ 代码 + 名称 + 备注 */
export interface ClassroomRow {
  /** 建筑简称（AC1/AC2/AC3/BOC/MMW/FYW/CMC…）或完整区域名 */
  building: string;
  /** 教室代码：课表/门牌上看到的那个，如 LT-1、P4702、6-213 */
  code: string;
  /** 教室名称：给人看的，如「讲堂 1」 */
  name: string;
  /** 备注（楼层等，可留空） */
  note: string;
}

/** 按区域解析出来的、准备新建的房间 */
export interface ClassroomRoomDraft {
  areaName: string;
  code: string;
  name: string;
  note: string;
}

/** 导入计划：要新建的区域 + 要新建的房间 + 被跳过的行数（已存在或格式不对） */
export interface ClassroomPlan {
  newAreas: string[];
  rooms: ClassroomRoomDraft[];
  skippedExisting: number;
}

/** 粘贴清单的解析结果（坏行单独回给界面，好让用户知道哪几行没认出来） */
export interface ClassroomParseResult {
  rows: ClassroomRow[];
  badLines: string[];
}

/** AC1 講堂数量（据城大臺灣學生會「教室地點」页：共 18 间，全在 4 樓） */
const AC1_LT_COUNT: number = 18;

function normKey(s: string): string {
  return s.replace(/\s+/g, '').toLowerCase();
}

/** 按简称（AC1/AC2/BOC…）取建筑区域全名；认不出就原样返回（当成用户自建的区域名） */
export function resolveAreaName(input: string): string {
  const raw: string = input.trim();
  if (raw.length === 0) {
    return '';
  }
  const k: string = normKey(raw);
  for (const b of cityuBuildings()) {
    const name: CampusBuilding = b;
    const full: string = normKey(name.name);
    // 建筑名形如「AC1 楊建文學術樓」，第一段就是学生日常用的简称
    const short: string = normKey(name.name.split(' ')[0]);
    if (full === k || short === k) {
      return name.name;
    }
  }
  return raw;
}

/** 建筑简称 → 备注（区域说明），建区域时用 */
export function buildingNoteOf(areaName: string): string {
  for (const b of cityuBuildings()) {
    if (b.name === areaName) {
      return b.note;
    }
  }
  return '';
}

/**
 * 内置种子清单：只放公开资料里能逐条查证的部分。
 * ⚠️ 18 间 LT 是按「共 18 间、全在 4 樓、不分颜色不标楼层」推出来的连号（LT-1…LT-18），
 * 公开资料只点名了 LT-8 作例子。导入前界面上会列出预览，导入后请按现场核对、随手增删。
 */
export function seedClassrooms(): ClassroomRow[] {
  const out: ClassroomRow[] = [];
  for (let i = 1; i <= AC1_LT_COUNT; i++) {
    out.push({
      building: 'AC1',
      code: `LT-${i}`,
      name: `讲堂 ${i}`,
      note: '4/F 讲堂'
    } as ClassroomRow);
  }
  // BOC 的 401 讲堂：城大臺灣學生會「教室地點」页在 BOC 条目下点名了 LT401
  out.push({
    building: 'BOC',
    code: 'LT401',
    name: '讲堂 401',
    note: 'BOC 综合楼'
  } as ClassroomRow);
  return out;
}

/** 一行拆分：优先逗号/制表/竖线/顿号；没有这些分隔符时退回按空白拆 */
function splitLine(line: string): string[] {
  let fields: string[] = [];
  if (/[,\t|、]/.test(line)) {
    fields = line.split(/[,\t|、]+/);
  } else {
    fields = line.split(/\s+/);
    // 「AC1 LT-1 讲堂 1」按空白拆会把名字也拆开，把第 4 段起并回名称
    if (fields.length > 3) {
      fields = [fields[0], fields[1], fields.slice(2).join(' ')];
    }
  }
  const out: string[] = [];
  for (const f of fields) {
    const t: string = f.trim();
    if (t.length > 0) {
      out.push(t);
    }
  }
  return out;
}

/**
 * 解析粘贴的清单。每行：`建筑, 教室代码, 教室名称, 备注(可选)`。
 * 分隔符支持 逗号 / 制表 / 竖线 / 顿号，也支持空格；`#` 或 `//` 开头的行当注释跳过。
 * 少于 3 段的行、或代码与名称都为空的行，归进 badLines（界面会提示有几行没认出来）。
 */
export function parseClassroomLines(text: string): ClassroomParseResult {
  const rows: ClassroomRow[] = [];
  const badLines: string[] = [];
  const lines: string[] = text.split(/\r?\n/);
  for (const raw of lines) {
    const line: string = raw.trim();
    if (line.length === 0 || line.startsWith('#') || line.startsWith('//')) {
      continue;
    }
    const f: string[] = splitLine(line);
    if (f.length < 3) {
      badLines.push(line);
      continue;
    }
    const building: string = f[0];
    const code: string = f[1];
    const name: string = f[2];
    const note: string = f.length > 3 ? f[3] : '';
    if (building.length === 0 || (code.length === 0 && name.length === 0)) {
      badLines.push(line);
      continue;
    }
    rows.push({ building: building, code: code, name: name, note: note } as ClassroomRow);
  }
  return { rows: rows, badLines: badLines } as ClassroomParseResult;
}

/**
 * 房间唯一性键。同一个区域里：有代码就按代码判重；没代码就按名称判重。
 * 两条键都会被检查，所以「同代码不同名」和「同名同代码」都算重复。
 */
export function roomKeysOf(areaName: string, code: string, name: string): string[] {
  const a: string = normKey(areaName);
  const out: string[] = [];
  const c: string = normKey(code);
  if (c.length > 0) {
    out.push(`${a}|#${c}`);
  }
  const n: string = normKey(name);
  if (n.length > 0) {
    out.push(`${a}|@${n}`);
  }
  return out;
}

/**
 * 规划导入：rows 是种子 + 粘贴合并后的清单。
 *  - knownAreaNames 里没有的建筑 → 进 newAreas（要新建区域）；
 *  - existingRoomKeys 是库里已有房间的键（用 roomKeysOf 生成，调用方拼好）；
 *  - 同名/同代码已存在的行直接跳过，所以重复导入是安全的。
 */
export function planClassrooms(rows: ClassroomRow[], knownAreaNames: string[],
  existingRoomKeys: string[]): ClassroomPlan {
  const areaNames: string[] = [];
  for (const n of knownAreaNames) {
    areaNames.push(n);
  }
  const taken: string[] = [];
  for (const k of existingRoomKeys) {
    taken.push(k);
  }
  const newAreas: string[] = [];
  const rooms: ClassroomRoomDraft[] = [];
  let skipped = 0;
  for (const row of rows) {
    const areaName: string = resolveAreaName(row.building);
    if (areaName.length === 0) {
      skipped++;
      continue;
    }
    const keys: string[] = roomKeysOf(areaName, row.code, row.name);
    if (keys.length === 0) {
      skipped++;
      continue;
    }
    let dup = false;
    for (const k of keys) {
      if (taken.indexOf(k) >= 0) {
        dup = true;
        break;
      }
    }
    if (dup) {
      skipped++;
      continue;
    }
    for (const k of keys) {
      taken.push(k);
    }
    if (areaNames.indexOf(areaName) < 0) {
      areaNames.push(areaName);
      newAreas.push(areaName);
    }
    rooms.push({
      areaName: areaName,
      code: row.code,
      name: row.name,
      note: row.note
    } as ClassroomRoomDraft);
  }
  return { newAreas: newAreas, rooms: rooms, skippedExisting: skipped } as ClassroomPlan;
}

/** 合并「内置种子 + 粘贴清单」（粘贴的排前面，用户写的优先） */
export function mergeRows(pasted: ClassroomRow[], seed: ClassroomRow[]): ClassroomRow[] {
  const out: ClassroomRow[] = [];
  for (const r of pasted) {
    out.push(r);
  }
  for (const r of seed) {
    out.push(r);
  }
  return out;
}
