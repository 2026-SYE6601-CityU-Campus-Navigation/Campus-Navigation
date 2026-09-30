/**
 * 校园静态数据：城大建筑 → 预置区域，以及记录节点时可选的楼层。
 *
 * 建筑名单来源（2026-09-28 查证）：
 *  - 香港城市大學（维基百科）「校園建築」一段列出的校內建築；
 *  - 城大臺灣學生會「教室地點」頁的簡寫對照：YEUNG=AC1、LI=AC2、LAU=AC3、
 *    BOC=中國銀行（香港）樓、CMC=邵逸夫創意媒體中心、MMW=蒙民偉樓、FYW=方潤華樓。
 *  - **邵逸夫圖書館在楊建文學術樓（AC1）內**，不是獨立一棟樓（維基：「1989年遷往九龍塘
 *    校園內楊建文學術樓」），所以不單列一座「邵逸夫樓」，只在 AC1 的備註裡說明。
 *  - 未收錄教職員宿舍（南山苑、德智苑）與歌和老街學生宿舍：那在校外，
 *    不是採集校園室內軌跡的對象。
 *
 * 樓層只是「城大常用的樓層寫法」（LG/F 為低層地下），各樓實際層數不同，
 * 記錄節點時也可以自己手填。
 */
export interface CampusBuilding {
  /** 区域名：常用简称 + 正式中文名（学生日常就按简称叫） */
  name: string;
  /** 备注：英文名 + 楼内值得留意的设施 */
  note: string;
}

export function cityuFloors(): Array<string> {
  return ['LG/F', 'G/F', '1/F', '2/F', '3/F', '4/F', '5/F', '6/F', '7/F', '8/F'];
}

export function cityuBuildings(): CampusBuilding[] {
  return [
    { name: 'AC1 楊建文學術樓', note: 'Yeung Kin Man Academic Building · 邵逸夫圖書館在此樓' },
    { name: 'AC2 李達三葉耀珍學術樓', note: 'Li Dak Sum Yip Yio Chin Academic Building' },
    { name: 'AC3 劉鳴煒學術樓', note: 'Lau Ming Wai Academic Building' },
    { name: 'BOC 中國銀行（香港）綜合樓', note: 'Bank of China (Hong Kong) Complex · 游泳池 / 校醫 / 學生發展處' },
    { name: 'MMW 蒙民偉樓', note: 'Mong Man Wai Building' },
    { name: 'FYW 方潤華樓', note: 'Fong Yun Wah Building' },
    { name: 'CMC 邵逸夫創意媒體中心', note: 'Run Run Shaw Creative Media Centre' },
    { name: '鄭翼之樓', note: 'Cheng Yick-chi Building' },
    { name: '學術交流大樓', note: 'Academic Exchange Building' },
    { name: '桃源樓', note: 'To Yuen Building' },
    { name: '賽馬會健康一體化大樓', note: 'Jockey Club One Health Tower' }
  ];
}

function normKey(s: string): string {
  return s.replace(/\s+/g, '').toLowerCase();
}

/** 这个区域名是不是城大的正式校园建筑（用于把老区域一次性归到「城市大学」分类） */
export function isCampusBuildingName(name: string): boolean {
  const k: string = normKey(name);
  if (k.length === 0) {
    return false;
  }
  for (const b of cityuBuildings()) {
    const full: string = normKey(b.name);
    // 建筑名形如「AC1 楊建文學術樓」，第一段就是学生日常用的简称
    const short: string = normKey(b.name.split(' ')[0]);
    // 认全名，也认「简称开头」（用户可能把区域改叫「AC1」或「AC1 三楼」）
    if (k === full || k.startsWith(short)) {
      return true;
    }
  }
  return false;
}

/** 要新建的建筑区域（同名区域跳过，所以重复导入是安全的） */
export function planBuildingAreas(existingNames: string[]): CampusBuilding[] {
  const taken: string[] = [];
  for (const n of existingNames) {
    taken.push(normKey(n));
  }
  const out: CampusBuilding[] = [];
  for (const b of cityuBuildings()) {
    const k: string = normKey(b.name);
    if (taken.indexOf(k) >= 0) {
      continue;
    }
    taken.push(k);
    out.push(b);
  }
  return out;
}
