import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Area, Marker, PhotoKind, Room, Track, TrackPhoto, TrackPhotoDraft, TrackPoint, TrackPointDraft, TrackTag, AREA_CATEGORY_CITYU, AREA_CATEGORY_TEST } from './Entities';
import { Ctx } from '../common/Utils';
import { isCampusBuildingName } from '../common/Campus';
import { FloorGuess, FloorObservation, FloorProbe, matchFloor, observationFrom } from '../common/FloorMatch';

export type DataListener = () => void;

/** 未分区约定 id：areaId 为 NULL 的记录在 UI 上用 0 表示 */
export const UNASSIGNED_AREA_ID = 0;

/**
 * 数据仓库：基于 HarmonyOS 关系型数据库（relationalStore，SQLite），
 * 等价于 Android 版的 Room。建表与 Android 版 room_marker.db 保持一致，
 * 新增 areas / track_tags / track_photos 三张表，并为 rooms / tracks /
 * track_points 追加 areaId / headingDeg 列（ALTER TABLE 迁移，兼容旧库）。
 *
 * 变更通知：所有写操作完成后回调已注册的监听器（页面订阅后自动刷新）。
 */
export class Store {
  private static rdb: relationalStore.RdbStore | null = null;
  private static ready: Promise<void> = Promise.resolve();
  private static listeners: DataListener[] = [];

  static init(context: common.UIAbilityContext): void {
    Store.ready = (async () => {
      const config: relationalStore.StoreConfig = {
        name: 'room_marker.db',
        securityLevel: relationalStore.SecurityLevel.S1
      };
      const rdb: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
      await rdb.executeSql(
        `CREATE TABLE IF NOT EXISTS rooms (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          code TEXT NOT NULL DEFAULT '',
          note TEXT NOT NULL DEFAULT '',
          areaId INTEGER,
          latitude REAL,
          longitude REAL,
          altitude REAL,
          pressureHpa REAL,
          createdAt INTEGER NOT NULL
        )`
      );
      await rdb.executeSql(
        `CREATE TABLE IF NOT EXISTS markers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          roomId INTEGER NOT NULL,
          name TEXT NOT NULL,
          markerType TEXT NOT NULL DEFAULT '自定义',
          latitude REAL,
          longitude REAL,
          altitude REAL,
          accuracy REAL,
          pressureHpa REAL,
          magneticX REAL,
          magneticY REAL,
          magneticZ REAL,
          createdAt INTEGER NOT NULL
        )`
      );
      await rdb.executeSql(
        `CREATE TABLE IF NOT EXISTS tracks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          areaId INTEGER,
          startedAt INTEGER NOT NULL,
          endedAt INTEGER,
          pointCount INTEGER NOT NULL DEFAULT 0
        )`
      );
      await rdb.executeSql(
        `CREATE TABLE IF NOT EXISTS track_points (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          trackId INTEGER NOT NULL,
          timeMs INTEGER NOT NULL,
          latitude REAL,
          longitude REAL,
          altitude REAL,
          accuracy REAL,
          pressureHpa REAL,
          magneticX REAL,
          magneticY REAL,
          magneticZ REAL,
          headingDeg REAL,
          wifiCount INTEGER NOT NULL DEFAULT 0,
          wifiTop TEXT NOT NULL DEFAULT ''
        )`
      );
      await rdb.executeSql(
        `CREATE TABLE IF NOT EXISTS areas (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          note TEXT NOT NULL DEFAULT '',
          category TEXT NOT NULL DEFAULT '城市大学',
          createdAt INTEGER NOT NULL
        )`
      );
      await rdb.executeSql(
        `CREATE TABLE IF NOT EXISTS track_tags (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          trackId INTEGER NOT NULL,
          timeMs INTEGER NOT NULL,
          tagType TEXT NOT NULL,
          note TEXT NOT NULL DEFAULT '',
          floor TEXT NOT NULL DEFAULT '',
          areaId INTEGER,
          latitude REAL,
          longitude REAL,
          altitude REAL,
          accuracy REAL,
          pressureHpa REAL,
          markerId INTEGER,
          headingDeg REAL,
          createdAt INTEGER NOT NULL
        )`
      );
      await rdb.executeSql(
        `CREATE TABLE IF NOT EXISTS track_photos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          trackId INTEGER NOT NULL,
          kind TEXT NOT NULL DEFAULT 'scenery',
          tagId INTEGER,
          timeMs INTEGER NOT NULL,
          filePath TEXT NOT NULL,
          note TEXT NOT NULL DEFAULT '',
          latitude REAL,
          longitude REAL,
          altitude REAL,
          headingDeg REAL,
          createdAt INTEGER NOT NULL
        )`
      );
      // 2026-09-29：键值设置表（上传地址、令牌等本机配置；与业务数据分开，不进导出包）
      await rdb.executeSql(
        `CREATE TABLE IF NOT EXISTS settings (
          k TEXT PRIMARY KEY,
          v TEXT NOT NULL DEFAULT ''
        )`
      );
      // 2026-09-29：楼层高度索引（用户要求「检测到在案的楼层高度就默认那个楼层」）。
      // 按「区域 + 楼层」一行，记下最近一次在该层采到的气压/海拔 —— 采集下一个节点时
      // 拿当前高度来比，落在容差内就把楼层名带出来（仍可手改）。判定逻辑在 common/FloorMatch。
      // 全新表，不需要 ALTER：两条路径都靠这条 CREATE 建出来。
      await rdb.executeSql(
        `CREATE TABLE IF NOT EXISTS floor_heights (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          areaId INTEGER NOT NULL,
          floorKey TEXT NOT NULL,
          floor TEXT NOT NULL,
          pressureHpa REAL,
          altitude REAL,
          updatedAt INTEGER NOT NULL
        )`
      );
      // 旧库迁移：列已存在时 ALTER 会报错，忽略即可
      try {
        await rdb.executeSql('ALTER TABLE rooms ADD COLUMN areaId INTEGER');
      } catch (e) {
      }
      try {
        await rdb.executeSql('ALTER TABLE tracks ADD COLUMN areaId INTEGER');
      } catch (e) {
      }
      try {
        await rdb.executeSql('ALTER TABLE track_points ADD COLUMN headingDeg REAL');
      } catch (e) {
      }
      // 2026-09-28：照片分「节点照 / 风景照」。默认值刻意取 scenery —— 升级前的老照片
      // 全部归为风景照（用户确认的归类规则），标签则原样保留并成为「节点」。
      try {
        await rdb.executeSql(
          `ALTER TABLE track_photos ADD COLUMN kind TEXT NOT NULL DEFAULT 'scenery'`);
      } catch (e) {
      }
      try {
        await rdb.executeSql('ALTER TABLE track_photos ADD COLUMN tagId INTEGER');
      } catch (e) {
      }
      // 2026-09-28：节点增加手填楼层（用户确认不做高度估算），老节点默认空字符串
      try {
        await rdb.executeSql(`ALTER TABLE track_tags ADD COLUMN floor TEXT NOT NULL DEFAULT ''`);
      } catch (e) {
      }
      // 2026-09-29：房间增加「教室代码」（教室名单里代码与名称是两样东西）；
      // 老房间没有代码，默认空字符串（列表里就只显示名称，与升级前一致）
      try {
        await rdb.executeSql(`ALTER TABLE rooms ADD COLUMN code TEXT NOT NULL DEFAULT ''`);
      } catch (e) {
      }
      // 2026-09-29：节点增加归属区域（跨楼轨迹里节点各归各楼）；老节点为 NULL = 沿用轨迹的区域
      try {
        await rdb.executeSql('ALTER TABLE track_tags ADD COLUMN areaId INTEGER');
      } catch (e) {
      }
      // 2026-09-29：节点增加气压（楼层高度索引的室内依据）与绑定标记 id（事后改绑房间时用它精确删旧标记）。
      // 老节点两条都是 NULL：气压没有就不参与高度比对吧（FloorMatch 里 undefined 直接跳过），
      // markerId 没有则改绑时无法自动清理旧房间里的标记，界面对老数据会如实提示。
      try {
        await rdb.executeSql('ALTER TABLE track_tags ADD COLUMN pressureHpa REAL');
      } catch (e) {
      }
      try {
        await rdb.executeSql('ALTER TABLE track_tags ADD COLUMN markerId INTEGER');
      } catch (e) {
      }
      // 2026-09-29（第二十五轮）：节点增加定位精度。老节点为 NULL = 没记过精度，
      // 口径与采样点一致（**没记精度不算差**），所以老数据不会突然被当成推算位置。
      try {
        await rdb.executeSql('ALTER TABLE track_tags ADD COLUMN accuracy REAL');
      } catch (e) {
      }
      // 2026-09-29：区域分两大类（城市大学 / 测试集）。老区域的默认值刻意给**空串**，
      // 好让下面那段一次性归类只处理「还没分类」的行；归完就不再有空串 → 天然幂等，
      // 也不会覆盖用户之后手改过的分类。全新安装走 CREATE 的默认值『城市大学』。
      try {
        await rdb.executeSql(`ALTER TABLE areas ADD COLUMN category TEXT NOT NULL DEFAULT ''`);
      } catch (e) {
      }
      // 一次性归类：老库里的区域按名字判定 —— 11 栋正式建筑 → 城市大学，其余 → 测试集
      // （用户 2026-09-29 确认的口径：库里已有的自己的测试区域要落到「测试集」）
      try {
        const ars: relationalStore.ResultSet =
          await rdb.querySql(`SELECT id, name FROM areas WHERE category = ''`);
        const areaIds: number[] = [];
        const areaNames: string[] = [];
        while (ars.goToNextRow()) {
          areaIds.push(ars.getLong(ars.getColumnIndex('id')));
          areaNames.push(ars.getString(ars.getColumnIndex('name')));
        }
        ars.close();
        for (let i = 0; i < areaIds.length; i++) {
          const catBucket: relationalStore.ValuesBucket = {
            'category': isCampusBuildingName(areaNames[i]) ? AREA_CATEGORY_CITYU : AREA_CATEGORY_TEST
          };
          const pb: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('areas');
          pb.equalTo('id', areaIds[i]);
          await rdb.update(catBucket, pb);
        }
      } catch (e) {
      }
      Store.rdb = rdb;
      Store.notify();
    })();
  }

  // ---------- 订阅 ----------

  static subscribe(listener: DataListener): void {
    Store.listeners.push(listener);
  }

  static unsubscribe(listener: DataListener): void {
    const index: number = Store.listeners.indexOf(listener);
    if (index >= 0) {
      Store.listeners.splice(index, 1);
    }
  }

  /**
   * 通知订阅者刷新界面。
   *
   * 每个监听器单独 try-catch：某个页面的刷新里抛了异常，不能影响其它页面，
   * 更不能顺着调用栈往上冒——否则写库已经成功（例如轨迹已落库），调用方拿到的却是 reject，
   * 界面上会误报「保存失败」。异常只记日志，不改变写操作的成败。
   */
  private static notify(): void {
    const copy: DataListener[] = Store.listeners.slice();
    for (const l of copy) {
      try {
        l();
      } catch (e) {
        hilog.warn(0x0000, 'RoomMarker', 'Store listener failed: %{public}s', JSON.stringify(e));
      }
    }
  }

  // ---------- 设置（键值） ----------

  /** 读设置项；不存在时返回默认值（上传地址这类本机配置都放这里） */
  static async getSetting(key: string, def: string): Promise<string> {
    await Store.ready;
    if (!Store.rdb) {
      return def;
    }
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('settings');
    p.equalTo('k', key);
    const rs: relationalStore.ResultSet = await Store.rdb.query(p, ['v']);
    let value: string = def;
    if (rs.goToNextRow()) {
      value = rs.getString(rs.getColumnIndex('v'));
    }
    rs.close();
    return value;
  }

  /** 写设置项（先 update 再按需 insert，避免依赖 SQL 方言；写失败会抛给调用方） */
  static async setSetting(key: string, value: string): Promise<void> {
    await Store.ready;
    if (!Store.rdb) {
      throw new Error('数据库未就绪，请重启应用后再试');
    }
    const bucket: relationalStore.ValuesBucket = {
      'k': key,
      'v': value
    };
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('settings');
    p.equalTo('k', key);
    const updated: number = await Store.rdb.update(bucket, p);
    if (updated === 0) {
      await Store.rdb.insert('settings', bucket);
    }
    Store.notify();
  }

  // ---------- 区域 ----------

  static async listAreas(): Promise<Area[]> {
    await Store.ready;
    if (!Store.rdb) {
      return [];
    }
    const rs: relationalStore.ResultSet = await Store.rdb.querySql(
      `SELECT a.id, a.name, a.note, a.category, a.createdAt,
        (SELECT COUNT(*) FROM rooms r WHERE r.areaId = a.id) AS roomCount,
        (SELECT COUNT(*) FROM tracks t WHERE t.areaId = a.id) AS trackCount
       FROM areas a ORDER BY a.createdAt ASC`
    );
    const out: Area[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        note: rs.getString(rs.getColumnIndex('note')),
        category: Store.optString(rs, 'category') ?? '',
        createdAt: rs.getLong(rs.getColumnIndex('createdAt')),
        roomCount: rs.getLong(rs.getColumnIndex('roomCount')),
        trackCount: rs.getLong(rs.getColumnIndex('trackCount'))
      });
    }
    rs.close();
    return out;
  }

  static async getArea(id: number): Promise<Area | undefined> {
    await Store.ready;
    if (!Store.rdb) {
      return undefined;
    }
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('areas');
    p.equalTo('id', id);
    const rs: relationalStore.ResultSet = await Store.rdb.query(
      p, ['id', 'name', 'note', 'category', 'createdAt']
    );
    let area: Area | undefined = undefined;
    if (rs.goToNextRow()) {
      area = {
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        note: rs.getString(rs.getColumnIndex('note')),
        category: Store.optString(rs, 'category') ?? '',
        createdAt: rs.getLong(rs.getColumnIndex('createdAt')),
        roomCount: 0,
        trackCount: 0
      };
    }
    rs.close();
    return area;
  }

  /** 新建区域，返回行 id。category 为两大类之一（城市大学 / 测试集），空串按「城市大学」落库 */
  static async insertArea(name: string, note: string, category: string): Promise<number> {
    await Store.ready;
    const bucket: relationalStore.ValuesBucket = {
      'name': name,
      'note': note,
      'category': category.length > 0 ? category : AREA_CATEGORY_CITYU,
      'createdAt': Date.now()
    };
    const rowId: number = await Store.rdb!.insert('areas', bucket);
    Store.notify();
    return rowId > 0 ? rowId : await Store.lastRowId('areas');
  }

  /** 改区域的分类（城市大学 / 测试集）。分类是自动归类出来的，给用户一个反悔的入口 */
  static async updateAreaCategory(id: number, category: string): Promise<void> {
    await Store.ready;
    const bucket: relationalStore.ValuesBucket = {
      'category': category.length > 0 ? category : AREA_CATEGORY_CITYU
    };
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('areas');
    p.equalTo('id', id);
    await Store.rdb!.update(bucket, p);
    Store.notify();
  }

  /** 删除区域：区域内的房间与轨迹全部移入未分区（不丢数据） */
  static async moveAreaToUnassigned(id: number): Promise<void> {
    await Store.ready;
    let bucket: relationalStore.ValuesBucket = { 'areaId': null };
    let p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('rooms');
    p.equalTo('areaId', id);
    await Store.rdb!.update(bucket, p);
    bucket = { 'areaId': null };
    p = new relationalStore.RdbPredicates('tracks');
    p.equalTo('areaId', id);
    await Store.rdb!.update(bucket, p);
    p = new relationalStore.RdbPredicates('areas');
    p.equalTo('id', id);
    await Store.rdb!.delete(p);
    Store.notify();
  }

  /** 彻底删除区域及其全部数据（房间+标记、轨迹+采样点+标签+照片文件） */
  static async deleteAreaCascade(id: number): Promise<void> {
    await Store.ready;
    // 先删轨迹（连带采样点/标签/照片文件），再删房间（连带标记），最后删区域
    const trackIds: number[] = await Store.trackIdsInArea(id);
    for (const tid of trackIds) {
      await Store.deleteTrack(tid);
    }
    let p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('rooms');
    p.equalTo('areaId', id);
    const rs: relationalStore.ResultSet = await Store.rdb!.query(p, ['id']);
    const roomIds: number[] = [];
    while (rs.goToNextRow()) {
      roomIds.push(rs.getLong(rs.getColumnIndex('id')));
    }
    rs.close();
    for (const rid of roomIds) {
      await Store.deleteRoom(rid);
    }
    p = new relationalStore.RdbPredicates('areas');
    p.equalTo('id', id);
    await Store.rdb!.delete(p);
    Store.notify();
  }

  // ---------- 读取 ----------

  /** 按区域列房间；areaId=0（未分区）查 NULL，undefined 查全部 */
  static async listRooms(areaId?: number): Promise<Room[]> {
    await Store.ready;
    if (!Store.rdb) {
      return [];
    }
    let p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('rooms');
    if (areaId !== undefined) {
      if (areaId === UNASSIGNED_AREA_ID) {
        p.isNull('areaId');
      } else {
        p.equalTo('areaId', areaId);
      }
    }
    p.orderByAsc('createdAt');
    const rs: relationalStore.ResultSet = await Store.rdb.query(
      p, ['id', 'name', 'code', 'note', 'areaId', 'latitude', 'longitude', 'altitude', 'pressureHpa', 'createdAt']
    );
    const out: Room[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        code: Store.optString(rs, 'code') ?? '',
        note: rs.getString(rs.getColumnIndex('note')),
        areaId: Store.optLong(rs, 'areaId'),
        latitude: Store.optDouble(rs, 'latitude'),
        longitude: Store.optDouble(rs, 'longitude'),
        altitude: Store.optDouble(rs, 'altitude'),
        pressureHpa: Store.optDouble(rs, 'pressureHpa'),
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      });
    }
    rs.close();
    return out;
  }

  static async getRoom(id: number): Promise<Room | undefined> {
    await Store.ready;
    if (!Store.rdb) {
      return undefined;
    }
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('rooms');
    p.equalTo('id', id);
    const rs: relationalStore.ResultSet = await Store.rdb.query(
      p, ['id', 'name', 'code', 'note', 'areaId', 'latitude', 'longitude', 'altitude', 'pressureHpa', 'createdAt']
    );
    let room: Room | undefined = undefined;
    if (rs.goToNextRow()) {
      room = {
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        code: Store.optString(rs, 'code') ?? '',
        note: rs.getString(rs.getColumnIndex('note')),
        areaId: Store.optLong(rs, 'areaId'),
        latitude: Store.optDouble(rs, 'latitude'),
        longitude: Store.optDouble(rs, 'longitude'),
        altitude: Store.optDouble(rs, 'altitude'),
        pressureHpa: Store.optDouble(rs, 'pressureHpa'),
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      };
    }
    rs.close();
    return room;
  }

  static async listMarkers(roomId: number): Promise<Marker[]> {
    await Store.ready;
    if (!Store.rdb) {
      return [];
    }
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('markers');
    p.equalTo('roomId', roomId);
    p.orderByAsc('createdAt');
    const rs: relationalStore.ResultSet = await Store.rdb.query(
      p,
      ['id', 'roomId', 'name', 'markerType', 'latitude', 'longitude', 'altitude', 'accuracy',
        'pressureHpa', 'magneticX', 'magneticY', 'magneticZ', 'createdAt']
    );
    const out: Marker[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        roomId: rs.getLong(rs.getColumnIndex('roomId')),
        name: rs.getString(rs.getColumnIndex('name')),
        markerType: rs.getString(rs.getColumnIndex('markerType')),
        latitude: Store.optDouble(rs, 'latitude'),
        longitude: Store.optDouble(rs, 'longitude'),
        altitude: Store.optDouble(rs, 'altitude'),
        accuracy: Store.optDouble(rs, 'accuracy'),
        pressureHpa: Store.optDouble(rs, 'pressureHpa'),
        magneticX: Store.optDouble(rs, 'magneticX'),
        magneticY: Store.optDouble(rs, 'magneticY'),
        magneticZ: Store.optDouble(rs, 'magneticZ'),
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      });
    }
    rs.close();
    return out;
  }

  static async listTracks(): Promise<Track[]> {
    await Store.ready;
    if (!Store.rdb) {
      return [];
    }
    const rs: relationalStore.ResultSet = await Store.rdb.querySql(
      `SELECT t.id, t.name, t.startedAt, t.endedAt, t.pointCount, t.areaId, a.name AS areaName
       FROM tracks t LEFT JOIN areas a ON t.areaId = a.id
       ORDER BY t.startedAt DESC`
    );
    const out: Track[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        startedAt: rs.getLong(rs.getColumnIndex('startedAt')),
        endedAt: Store.optLong(rs, 'endedAt'),
        pointCount: rs.getLong(rs.getColumnIndex('pointCount')),
        areaId: Store.optLong(rs, 'areaId'),
        areaName: Store.optString(rs, 'areaName')
      });
    }
    rs.close();
    return out;
  }

  /** 按区域列轨迹；areaId=0（未分区）查 NULL */
  static async listTracksInArea(areaId: number): Promise<Track[]> {
    await Store.ready;
    if (!Store.rdb) {
      return [];
    }
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('tracks');
    if (areaId === UNASSIGNED_AREA_ID) {
      p.isNull('areaId');
    } else {
      p.equalTo('areaId', areaId);
    }
    p.orderByDesc('startedAt');
    const rs: relationalStore.ResultSet = await Store.rdb.query(
      p, ['id', 'name', 'startedAt', 'endedAt', 'pointCount', 'areaId']
    );
    const out: Track[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        startedAt: rs.getLong(rs.getColumnIndex('startedAt')),
        endedAt: Store.optLong(rs, 'endedAt'),
        pointCount: rs.getLong(rs.getColumnIndex('pointCount')),
        areaId: Store.optLong(rs, 'areaId')
      });
    }
    rs.close();
    return out;
  }

  static async getTrack(id: number): Promise<Track | undefined> {
    await Store.ready;
    if (!Store.rdb) {
      return undefined;
    }
    const rs: relationalStore.ResultSet = await Store.rdb.querySql(
      `SELECT t.id, t.name, t.startedAt, t.endedAt, t.pointCount, t.areaId, a.name AS areaName
       FROM tracks t LEFT JOIN areas a ON t.areaId = a.id WHERE t.id = ${id}`
    );
    let track: Track | undefined = undefined;
    if (rs.goToNextRow()) {
      track = {
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        startedAt: rs.getLong(rs.getColumnIndex('startedAt')),
        endedAt: Store.optLong(rs, 'endedAt'),
        pointCount: rs.getLong(rs.getColumnIndex('pointCount')),
        areaId: Store.optLong(rs, 'areaId'),
        areaName: Store.optString(rs, 'areaName')
      };
    }
    rs.close();
    return track;
  }

  static async listPoints(trackId: number): Promise<TrackPoint[]> {
    await Store.ready;
    if (!Store.rdb) {
      return [];
    }
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('track_points');
    p.equalTo('trackId', trackId);
    p.orderByAsc('timeMs');
    const rs: relationalStore.ResultSet = await Store.rdb.query(
      p,
      ['id', 'trackId', 'timeMs', 'latitude', 'longitude', 'altitude', 'accuracy',
        'pressureHpa', 'magneticX', 'magneticY', 'magneticZ', 'headingDeg', 'wifiCount', 'wifiTop']
    );
    const out: TrackPoint[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        trackId: rs.getLong(rs.getColumnIndex('trackId')),
        timeMs: rs.getLong(rs.getColumnIndex('timeMs')),
        latitude: Store.optDouble(rs, 'latitude'),
        longitude: Store.optDouble(rs, 'longitude'),
        altitude: Store.optDouble(rs, 'altitude'),
        accuracy: Store.optDouble(rs, 'accuracy'),
        pressureHpa: Store.optDouble(rs, 'pressureHpa'),
        magneticX: Store.optDouble(rs, 'magneticX'),
        magneticY: Store.optDouble(rs, 'magneticY'),
        magneticZ: Store.optDouble(rs, 'magneticZ'),
        headingDeg: Store.optDouble(rs, 'headingDeg'),
        wifiCount: rs.getLong(rs.getColumnIndex('wifiCount')),
        wifiTop: rs.getString(rs.getColumnIndex('wifiTop'))
      });
    }
    rs.close();
    return out;
  }

  static async listTrackTags(trackId: number): Promise<TrackTag[]> {
    await Store.ready;
    if (!Store.rdb) {
      return [];
    }
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('track_tags');
    p.equalTo('trackId', trackId);
    p.orderByAsc('timeMs');
    const rs: relationalStore.ResultSet = await Store.rdb.query(
      p,
      ['id', 'trackId', 'timeMs', 'tagType', 'note', 'floor', 'areaId', 'latitude', 'longitude',
        'altitude', 'accuracy', 'pressureHpa', 'markerId', 'headingDeg', 'createdAt']
    );
    const out: TrackTag[] = [];
    while (rs.goToNextRow()) {
      const floor: string | undefined = Store.optString(rs, 'floor');
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        trackId: rs.getLong(rs.getColumnIndex('trackId')),
        timeMs: rs.getLong(rs.getColumnIndex('timeMs')),
        tagType: rs.getString(rs.getColumnIndex('tagType')),
        note: rs.getString(rs.getColumnIndex('note')),
        floor: floor === undefined ? '' : floor,
        areaId: Store.optLong(rs, 'areaId'),
        latitude: Store.optDouble(rs, 'latitude'),
        longitude: Store.optDouble(rs, 'longitude'),
        altitude: Store.optDouble(rs, 'altitude'),
        accuracy: Store.optDouble(rs, 'accuracy'),
        pressureHpa: Store.optDouble(rs, 'pressureHpa'),
        markerId: Store.optLong(rs, 'markerId'),
        headingDeg: Store.optDouble(rs, 'headingDeg'),
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      });
    }
    rs.close();
    return out;
  }

  static async listTrackPhotos(trackId: number): Promise<TrackPhoto[]> {
    await Store.ready;
    if (!Store.rdb) {
      return [];
    }
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('track_photos');
    p.equalTo('trackId', trackId);
    p.orderByAsc('timeMs');
    const rs: relationalStore.ResultSet = await Store.rdb.query(
      p,
      ['id', 'trackId', 'kind', 'tagId', 'timeMs', 'filePath', 'note', 'latitude', 'longitude',
        'altitude', 'headingDeg', 'createdAt']
    );
    const out: TrackPhoto[] = [];
    while (rs.goToNextRow()) {
      const kind: string | undefined = Store.optString(rs, 'kind');
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        trackId: rs.getLong(rs.getColumnIndex('trackId')),
        kind: kind === undefined ? PhotoKind.SCENERY : kind,
        tagId: Store.optLong(rs, 'tagId'),
        timeMs: rs.getLong(rs.getColumnIndex('timeMs')),
        filePath: rs.getString(rs.getColumnIndex('filePath')),
        note: rs.getString(rs.getColumnIndex('note')),
        latitude: Store.optDouble(rs, 'latitude'),
        longitude: Store.optDouble(rs, 'longitude'),
        altitude: Store.optDouble(rs, 'altitude'),
        headingDeg: Store.optDouble(rs, 'headingDeg'),
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      });
    }
    rs.close();
    return out;
  }

  // ---------- 写入 ----------

  /** 新建房间，返回行 id。areaId 为 0/undefined 时归入未分区；code 为教室代码（普通房间留空） */
  static async insertRoom(name: string, note: string, areaId?: number, code?: string): Promise<number> {
    await Store.ready;
    const bucket: relationalStore.ValuesBucket = {
      'name': name,
      'code': code ?? '',
      'note': note,
      'createdAt': Date.now()
    };
    if (areaId !== undefined && areaId !== UNASSIGNED_AREA_ID) {
      bucket['areaId'] = areaId;
    }
    const rowId: number = await Store.rdb!.insert('rooms', bucket);
    Store.notify();
    return rowId > 0 ? rowId : await Store.lastRowId('rooms');
  }

  /** 更新房间基准点（经纬度/海拔/气压） */
  static async updateRoomBase(roomId: number, latitude?: number, longitude?: number,
    altitude?: number, pressureHpa?: number): Promise<void> {
    await Store.ready;
    const bucket: relationalStore.ValuesBucket = {};
    if (latitude !== undefined) {
      bucket['latitude'] = latitude;
    }
    if (longitude !== undefined) {
      bucket['longitude'] = longitude;
    }
    if (altitude !== undefined) {
      bucket['altitude'] = altitude;
    }
    if (pressureHpa !== undefined) {
      bucket['pressureHpa'] = pressureHpa;
    }
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('rooms');
    p.equalTo('id', roomId);
    await Store.rdb!.update(bucket, p);
    Store.notify();
  }

  static async deleteRoom(id: number): Promise<void> {
    await Store.ready;
    let p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('rooms');
    p.equalTo('id', id);
    await Store.rdb!.delete(p);
    // 级联删除子标记（SQLite 外键默认关闭，手动删）
    p = new relationalStore.RdbPredicates('markers');
    p.equalTo('roomId', id);
    await Store.rdb!.delete(p);
    Store.notify();
  }

  /** 往房间写一条标记，返回行 id（节点要用它记住「我绑的是哪条标记」，见 syncTagMarker） */
  static async insertMarker(roomId: number, name: string, markerType: string,
    latitude?: number, longitude?: number, altitude?: number, accuracy?: number,
    pressureHpa?: number, magneticX?: number, magneticY?: number,
    magneticZ?: number): Promise<number> {
    await Store.ready;
    const bucket: relationalStore.ValuesBucket = {
      'roomId': roomId,
      'name': name,
      'markerType': markerType,
      'createdAt': Date.now()
    };
    Store.putOpt(bucket, 'latitude', latitude);
    Store.putOpt(bucket, 'longitude', longitude);
    Store.putOpt(bucket, 'altitude', altitude);
    Store.putOpt(bucket, 'accuracy', accuracy);
    Store.putOpt(bucket, 'pressureHpa', pressureHpa);
    Store.putOpt(bucket, 'magneticX', magneticX);
    Store.putOpt(bucket, 'magneticY', magneticY);
    Store.putOpt(bucket, 'magneticZ', magneticZ);
    const rowId: number = await Store.rdb!.insert('markers', bucket);
    Store.notify();
    return rowId > 0 ? rowId : await Store.lastRowId('markers');
  }

  /** 按 id 取一条标记（编辑节点时要据此判断「旧标记在哪个房间」，才能决定原地更新还是搬走） */
  static async getMarker(id: number): Promise<Marker | undefined> {
    await Store.ready;
    if (!Store.rdb || id <= 0) {
      return undefined;
    }
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('markers');
    p.equalTo('id', id);
    const rs: relationalStore.ResultSet = await Store.rdb.query(p,
      ['id', 'roomId', 'name', 'markerType', 'latitude', 'longitude', 'altitude', 'accuracy',
        'pressureHpa', 'createdAt']);
    let out: Marker | undefined = undefined;
    if (rs.goToNextRow()) {
      out = {
        id: rs.getLong(rs.getColumnIndex('id')),
        roomId: rs.getLong(rs.getColumnIndex('roomId')),
        name: rs.getString(rs.getColumnIndex('name')),
        markerType: rs.getString(rs.getColumnIndex('markerType')),
        latitude: Store.optDouble(rs, 'latitude'),
        longitude: Store.optDouble(rs, 'longitude'),
        altitude: Store.optDouble(rs, 'altitude'),
        accuracy: Store.optDouble(rs, 'accuracy'),
        pressureHpa: Store.optDouble(rs, 'pressureHpa'),
        createdAt: rs.getLong(rs.getColumnIndex('createdAt'))
      };
    }
    rs.close();
    return out;
  }

  /** 改标记的名字与类型（备注从「西侧铁门」改成「东侧铁门」时，房间页那条标记也要跟着变） */
  static async updateMarkerLabel(id: number, name: string, markerType: string): Promise<void> {
    await Store.ready;
    const bucket: relationalStore.ValuesBucket = {
      'name': name,
      'markerType': markerType
    };
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('markers');
    p.equalTo('id', id);
    await Store.rdb!.update(bucket, p);
    Store.notify();
  }

  static async deleteMarker(id: number): Promise<void> {
    await Store.ready;
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('markers');
    p.equalTo('id', id);
    await Store.rdb!.delete(p);
    Store.notify();
  }

  /** 新建轨迹会话，返回行 id。areaId 必填（UI 层强制先选区域） */
  static async insertTrack(name: string, areaId: number): Promise<number> {
    await Store.ready;
    const bucket: relationalStore.ValuesBucket = {
      'name': name,
      'areaId': areaId,
      'startedAt': Date.now(),
      'pointCount': 0
    };
    const rowId: number = await Store.rdb!.insert('tracks', bucket);
    Store.notify();
    return rowId > 0 ? rowId : await Store.lastRowId('tracks');
  }

  static async insertPoints(points: TrackPointDraft[]): Promise<void> {
    await Store.ready;
    if (points.length === 0) {
      return;
    }
    for (const pt of points) {
      const bucket: relationalStore.ValuesBucket = {
        'trackId': pt.trackId,
        'timeMs': pt.timeMs,
        'wifiCount': pt.wifiCount,
        'wifiTop': pt.wifiTop
      };
      Store.putOpt(bucket, 'latitude', pt.latitude);
      Store.putOpt(bucket, 'longitude', pt.longitude);
      Store.putOpt(bucket, 'altitude', pt.altitude);
      Store.putOpt(bucket, 'accuracy', pt.accuracy);
      Store.putOpt(bucket, 'pressureHpa', pt.pressureHpa);
      Store.putOpt(bucket, 'magneticX', pt.magneticX);
      Store.putOpt(bucket, 'magneticY', pt.magneticY);
      Store.putOpt(bucket, 'magneticZ', pt.magneticZ);
      Store.putOpt(bucket, 'headingDeg', pt.headingDeg);
      await Store.rdb!.insert('track_points', bucket);
    }
    // 采样点变化不影响列表页展示，无需 notify
  }

  static async finishTrack(id: number, endedAt: number, pointCount: number): Promise<void> {
    await Store.ready;
    const bucket: relationalStore.ValuesBucket = {
      'endedAt': endedAt,
      'pointCount': pointCount
    };
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('tracks');
    p.equalTo('id', id);
    await Store.rdb!.update(bucket, p);
    Store.notify();
  }

  static async deleteTrack(id: number): Promise<void> {
    await Store.ready;
    // 先删照片文件（沙箱），再删记录
    try {
      const photos: TrackPhoto[] = await Store.listTrackPhotos(id);
      Store.unlinkFiles(photos.map((ph: TrackPhoto) => ph.filePath));
    } catch (e) {
    }
    let p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('tracks');
    p.equalTo('id', id);
    await Store.rdb!.delete(p);
    // 级联删除采样点/标签/照片记录
    p = new relationalStore.RdbPredicates('track_points');
    p.equalTo('trackId', id);
    await Store.rdb!.delete(p);
    p = new relationalStore.RdbPredicates('track_tags');
    p.equalTo('trackId', id);
    await Store.rdb!.delete(p);
    p = new relationalStore.RdbPredicates('track_photos');
    p.equalTo('trackId', id);
    await Store.rdb!.delete(p);
    Store.notify();
  }

  /** 新建节点（原「标签」），返回行 id —— 节点照要用它做 tagId 关联。
   *  floor 为手填楼层（可留空）；areaId 为节点归属的区域（-1 = 不分区域，存 NULL）；
   *  pressureHpa 为打点时的气压、accuracy 为打点时的定位精度（参数放在最后，
   *  是为了不打乱既有调用点的位置语义）。 */
  static async insertTrackTag(trackId: number, timeMs: number, tagType: string, note: string,
    floor: string, areaId: number, latitude?: number, longitude?: number, altitude?: number,
    headingDeg?: number, pressureHpa?: number, accuracy?: number): Promise<number> {
    await Store.ready;
    const bucket: relationalStore.ValuesBucket = {
      'trackId': trackId,
      'timeMs': timeMs,
      'tagType': tagType,
      'note': note,
      'floor': floor,
      'createdAt': Date.now()
    };
    if (areaId > 0) {
      bucket['areaId'] = areaId;
    }
    Store.putOpt(bucket, 'latitude', latitude);
    Store.putOpt(bucket, 'longitude', longitude);
    Store.putOpt(bucket, 'altitude', altitude);
    Store.putOpt(bucket, 'pressureHpa', pressureHpa);
    Store.putOpt(bucket, 'headingDeg', headingDeg);
    Store.putOpt(bucket, 'accuracy', accuracy);
    const rowId: number = await Store.rdb!.insert('track_tags', bucket);
    Store.notify();
    return rowId > 0 ? rowId : await Store.lastRowId('track_tags');
  }

  /**
   * 事后修正一个节点（用户 2026-09-29 要求「标记错了要能在 APP 里改」）。
   * 只改**填错的那几栏**：类型 / 备注 / 楼层 / 区域。位置（经纬度/海拔/气压）是实测值，
   * 本轮不提供修改（用户确认「先不做改位置」），保持数据的可信度。
   * areaId <= 0 会写成 NULL（＝沿用轨迹的区域），所以「改成未分区」是真能改回去的。
   */
  static async updateTrackTag(id: number, tagType: string, note: string, floor: string,
    areaId: number): Promise<void> {
    await Store.ready;
    const bucket: relationalStore.ValuesBucket = {
      'tagType': tagType,
      'note': note,
      'floor': floor,
      'areaId': areaId > 0 ? areaId : null
    };
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('track_tags');
    p.equalTo('id', id);
    await Store.rdb!.update(bucket, p);
    Store.notify();
  }

  /** 把节点记住的「我绑的是哪条房间标记」写回去 */
  static async setTagMarker(tagId: number, markerId: number): Promise<void> {
    await Store.ready;
    if (markerId <= 0) {
      return;
    }
    const bucket: relationalStore.ValuesBucket = { 'markerId': markerId };
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('track_tags');
    p.equalTo('id', tagId);
    await Store.rdb!.update(bucket, p);
    // 不改动列表展示，无需 notify
  }

  /**
   * 让「房间标记」跟上节点的最新状态（记录节点时、以及事后编辑节点时都走这里）。
   *
   * 为什么要有它：门 / 门禁节点绑房间并不是直接写进节点字段，而是**往那个房间插一条标记**。
   * 于是「把节点改绑到另一个房间」必须先把旧房间里那条标记删掉，否则房间页会一直挂着一条
   * 指向错误位置的标记。用户 2026-09-29 明确要能修正「区域 / 绑定房间选错」的节点。
   *
   * 三种情况：
   *  - roomId <= 0（不绑 / 解绑）：删掉旧标记（如果有）
   *  - roomId > 0 且旧标记就在这个房间：**原地改**名字与类型 —— 标记上还挂着精度、磁力三轴这些
   *    只在标记里存的采样值（室内定位研究要用），删了重建就没了
   *  - roomId > 0 且换了房间（或本来没标记）：删旧建新，并把新标记 id 记回节点
   *
   * 返回现在的标记 id（0 = 现在没有标记）。
   */
  static async syncTagMarker(tagId: number, markerId: number, roomId: number, name: string,
    markerType: string, latitude?: number, longitude?: number, altitude?: number,
    pressureHpa?: number): Promise<number> {
    await Store.ready;
    if (roomId <= 0) {
      if (markerId > 0) {
        await Store.deleteMarker(markerId);
      }
      return 0;
    }
    if (markerId > 0) {
      const old: Marker | undefined = await Store.getMarker(markerId);
      if (old !== undefined && old.roomId === roomId) {
        await Store.updateMarkerLabel(markerId, name, markerType);
        return markerId;
      }
      if (old !== undefined) {
        await Store.deleteMarker(markerId);
      }
    }
    const newId: number = await Store.insertMarker(roomId, name, markerType,
      latitude, longitude, altitude, undefined, pressureHpa);
    await Store.setTagMarker(tagId, newId);
    return newId;
  }

  // ---------- 楼层高度索引 ----------

  /**
   * 学一条「这个区域的这一层 ≈ 这个高度」。同区域同层只留最近一次（先删后插），
   * 所以反复采同一层不会越积越多，也会随最近一次实测更新。
   * areaId <= 0（未分区）不学：未分区会把好几栋楼混在一起，学出来的是错的高度。
   */
  static async learnFloorHeight(areaId: number, floor: string, probe: FloorProbe): Promise<void> {
    await Store.ready;
    if (areaId <= 0) {
      return;
    }
    if (probe.pressureHpa === undefined && probe.altitude === undefined) {
      return;
    }
    // 归一化键由 observationFrom 统一算（与 Track3D 的图层分组同一套口径）
    const obs: FloorObservation = observationFrom(floor, probe, Date.now());
    if (obs.key.length === 0) {
      return;
    }
    const del: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('floor_heights');
    del.equalTo('areaId', areaId);
    del.equalTo('floorKey', obs.key);
    await Store.rdb!.delete(del);
    const bucket: relationalStore.ValuesBucket = {
      'areaId': areaId,
      'floorKey': obs.key,
      'floor': obs.floor,
      'updatedAt': obs.updatedAt
    };
    Store.putOpt(bucket, 'pressureHpa', obs.pressureHpa);
    Store.putOpt(bucket, 'altitude', obs.altitude);
    await Store.rdb!.insert('floor_heights', bucket);
    // 楼层索引只在采集时读，不影响列表页展示，无需 notify
  }

  /** 按当前实测高度推测楼层（只认这个区域里已经记过的楼层）；猜不出来时 floor 为空串 */
  static async matchFloorHeight(areaId: number, probe: FloorProbe): Promise<FloorGuess> {
    await Store.ready;
    const empty: FloorGuess = { floor: '', by: '' };
    if (!Store.rdb || areaId <= 0) {
      return empty;
    }
    if (probe.pressureHpa === undefined && probe.altitude === undefined) {
      return empty;
    }
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('floor_heights');
    p.equalTo('areaId', areaId);
    const rs: relationalStore.ResultSet = await Store.rdb.query(p,
      ['floorKey', 'floor', 'pressureHpa', 'altitude', 'updatedAt']);
    const obs: FloorObservation[] = [];
    while (rs.goToNextRow()) {
      obs.push({
        key: rs.getString(rs.getColumnIndex('floorKey')),
        floor: rs.getString(rs.getColumnIndex('floor')),
        pressureHpa: Store.optDouble(rs, 'pressureHpa'),
        altitude: Store.optDouble(rs, 'altitude'),
        updatedAt: rs.getLong(rs.getColumnIndex('updatedAt'))
      });
    }
    rs.close();
    return matchFloor(obs, probe, Date.now());
  }

  /** 插入一条照片记录（节点照带 kind='node' 与 tagId，风景照 kind='scenery'），返回行 id */
  static async insertTrackPhoto(draft: TrackPhotoDraft): Promise<number> {
    await Store.ready;
    const bucket: relationalStore.ValuesBucket = {
      'trackId': draft.trackId,
      'kind': draft.kind,
      'timeMs': draft.timeMs,
      'filePath': draft.filePath,
      'note': draft.note,
      'createdAt': Date.now()
    };
    Store.putOpt(bucket, 'tagId', draft.tagId);
    Store.putOpt(bucket, 'latitude', draft.latitude);
    Store.putOpt(bucket, 'longitude', draft.longitude);
    Store.putOpt(bucket, 'altitude', draft.altitude);
    Store.putOpt(bucket, 'headingDeg', draft.headingDeg);
    const rowId: number = await Store.rdb!.insert('track_photos', bucket);
    Store.notify();
    return rowId > 0 ? rowId : await Store.lastRowId('track_photos');
  }

  /** 删除节点：连带删除它名下的节点照（含沙箱文件），避免留下孤儿照片 */
  static async deleteTrackTag(id: number): Promise<void> {
    await Store.ready;
    await Store.deletePhotosOfTag(id);
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('track_tags');
    p.equalTo('id', id);
    await Store.rdb!.delete(p);
    Store.notify();
  }

  /** 删除某个节点名下的全部照片：先删文件再删记录 */
  private static async deletePhotosOfTag(tagId: number): Promise<void> {
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('track_photos');
    p.equalTo('tagId', tagId);
    const rs: relationalStore.ResultSet = await Store.rdb!.query(p, ['id', 'filePath']);
    const ids: number[] = [];
    const files: string[] = [];
    while (rs.goToNextRow()) {
      ids.push(rs.getLong(rs.getColumnIndex('id')));
      files.push(rs.getString(rs.getColumnIndex('filePath')));
    }
    rs.close();
    Store.unlinkFiles(files);
    for (const pid of ids) {
      const dp: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('track_photos');
      dp.equalTo('id', pid);
      await Store.rdb!.delete(dp);
    }
  }

  static async deleteTrackPhoto(id: number): Promise<void> {
    await Store.ready;
    // 先取文件路径把沙箱文件删掉，再删记录
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('track_photos');
    p.equalTo('id', id);
    const rs: relationalStore.ResultSet = await Store.rdb!.query(p, ['filePath']);
    let filePath = '';
    if (rs.goToNextRow()) {
      filePath = rs.getString(rs.getColumnIndex('filePath'));
    }
    rs.close();
    if (filePath.length > 0) {
      Store.unlinkFiles([filePath]);
    }
    const dp: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('track_photos');
    dp.equalTo('id', id);
    await Store.rdb!.delete(dp);
    Store.notify();
  }

  /** 批量删除沙箱内的照片文件（记录已被删或文件不存在都忽略） */
  private static unlinkFiles(relPaths: string[]): void {
    const dir: string = Ctx.ui ? Ctx.ui.filesDir : '';
    if (dir.length === 0) {
      return;
    }
    for (const rel of relPaths) {
      if (rel.length === 0) {
        continue;
      }
      try {
        fs.unlinkSync(`${dir}/${rel}`);
      } catch (e) {
      }
    }
  }

  // ---------- 工具 ----------

  private static async trackIdsInArea(areaId: number): Promise<number[]> {
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('tracks');
    if (areaId === UNASSIGNED_AREA_ID) {
      p.isNull('areaId');
    } else {
      p.equalTo('areaId', areaId);
    }
    const rs: relationalStore.ResultSet = await Store.rdb!.query(p, ['id']);
    const out: number[] = [];
    while (rs.goToNextRow()) {
      out.push(rs.getLong(rs.getColumnIndex('id')));
    }
    rs.close();
    return out;
  }

  private static optDouble(rs: relationalStore.ResultSet, column: string): number | undefined {
    const index: number = rs.getColumnIndex(column);
    return rs.isColumnNull(index) ? undefined : rs.getDouble(index);
  }

  private static optLong(rs: relationalStore.ResultSet, column: string): number | undefined {
    const index: number = rs.getColumnIndex(column);
    return rs.isColumnNull(index) ? undefined : rs.getLong(index);
  }

  private static optString(rs: relationalStore.ResultSet, column: string): string | undefined {
    const index: number = rs.getColumnIndex(column);
    return rs.isColumnNull(index) ? undefined : rs.getString(index);
  }

  private static putOpt(bucket: relationalStore.ValuesBucket, key: string, value?: number): void {
    if (value !== undefined) {
      bucket[key] = value;
    }
  }

  private static async lastRowId(table: string): Promise<number> {
    const rs: relationalStore.ResultSet = await Store.rdb!.querySql(`SELECT MAX(id) AS mid FROM ${table}`);
    let id = 0;
    if (rs.goToNextRow()) {
      id = rs.getLong(rs.getColumnIndex('mid'));
    }
    rs.close();
    return id;
  }
}
