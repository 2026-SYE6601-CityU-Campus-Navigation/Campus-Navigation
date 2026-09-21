import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Area, Marker, Room, Track, TrackPhoto, TrackPoint, TrackPointDraft, TrackTag } from './Entities';
import { Ctx } from '../common/Utils';

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
          note TEXT NOT NULL DEFAULT '',
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
          wifiCount INTEGER NOT NULL DEFAULT 0,
          wifiTop TEXT NOT NULL DEFAULT ''
        )`
      );
      await rdb.executeSql(
        `CREATE TABLE IF NOT EXISTS areas (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          note TEXT NOT NULL DEFAULT '',
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
          latitude REAL,
          longitude REAL,
          altitude REAL,
          headingDeg REAL,
          createdAt INTEGER NOT NULL
        )`
      );
      await rdb.executeSql(
        `CREATE TABLE IF NOT EXISTS track_photos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          trackId INTEGER NOT NULL,
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

  private static notify(): void {
    const copy: DataListener[] = Store.listeners.slice();
    copy.forEach((l: DataListener) => {
      l();
    });
  }

  // ---------- 区域 ----------

  static async listAreas(): Promise<Area[]> {
    await Store.ready;
    if (!Store.rdb) {
      return [];
    }
    const rs: relationalStore.ResultSet = await Store.rdb.querySql(
      `SELECT a.id, a.name, a.note, a.createdAt,
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
      p, ['id', 'name', 'note', 'createdAt']
    );
    let area: Area | undefined = undefined;
    if (rs.goToNextRow()) {
      area = {
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
        note: rs.getString(rs.getColumnIndex('note')),
        createdAt: rs.getLong(rs.getColumnIndex('createdAt')),
        roomCount: 0,
        trackCount: 0
      };
    }
    rs.close();
    return area;
  }

  static async insertArea(name: string, note: string): Promise<number> {
    await Store.ready;
    const bucket: relationalStore.ValuesBucket = {
      'name': name,
      'note': note,
      'createdAt': Date.now()
    };
    const rowId: number = await Store.rdb!.insert('areas', bucket);
    Store.notify();
    return rowId > 0 ? rowId : await Store.lastRowId('areas');
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
      p, ['id', 'name', 'note', 'areaId', 'latitude', 'longitude', 'altitude', 'pressureHpa', 'createdAt']
    );
    const out: Room[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
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
      p, ['id', 'name', 'note', 'areaId', 'latitude', 'longitude', 'altitude', 'pressureHpa', 'createdAt']
    );
    let room: Room | undefined = undefined;
    if (rs.goToNextRow()) {
      room = {
        id: rs.getLong(rs.getColumnIndex('id')),
        name: rs.getString(rs.getColumnIndex('name')),
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
      ['id', 'trackId', 'timeMs', 'tagType', 'note', 'latitude', 'longitude', 'altitude', 'headingDeg', 'createdAt']
    );
    const out: TrackTag[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        trackId: rs.getLong(rs.getColumnIndex('trackId')),
        timeMs: rs.getLong(rs.getColumnIndex('timeMs')),
        tagType: rs.getString(rs.getColumnIndex('tagType')),
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
      ['id', 'trackId', 'timeMs', 'filePath', 'note', 'latitude', 'longitude', 'altitude', 'headingDeg', 'createdAt']
    );
    const out: TrackPhoto[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        trackId: rs.getLong(rs.getColumnIndex('trackId')),
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

  /** 新建房间，返回行 id。areaId 为 0/undefined 时归入未分区 */
  static async insertRoom(name: string, note: string, areaId?: number): Promise<number> {
    await Store.ready;
    const bucket: relationalStore.ValuesBucket = {
      'name': name,
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

  static async insertMarker(roomId: number, name: string, markerType: string,
    latitude?: number, longitude?: number, altitude?: number, accuracy?: number,
    pressureHpa?: number, magneticX?: number, magneticY?: number, magneticZ?: number): Promise<void> {
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
    await Store.rdb!.insert('markers', bucket);
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
      const dir: string = Ctx.ui ? Ctx.ui.filesDir : '';
      for (const ph of photos) {
        if (dir.length > 0) {
          try {
            fs.unlinkSync(`${dir}/${ph.filePath}`);
          } catch (e) {
          }
        }
      }
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

  static async insertTrackTag(trackId: number, timeMs: number, tagType: string, note: string,
    latitude?: number, longitude?: number, altitude?: number, headingDeg?: number): Promise<void> {
    await Store.ready;
    const bucket: relationalStore.ValuesBucket = {
      'trackId': trackId,
      'timeMs': timeMs,
      'tagType': tagType,
      'note': note,
      'createdAt': Date.now()
    };
    Store.putOpt(bucket, 'latitude', latitude);
    Store.putOpt(bucket, 'longitude', longitude);
    Store.putOpt(bucket, 'altitude', altitude);
    Store.putOpt(bucket, 'headingDeg', headingDeg);
    await Store.rdb!.insert('track_tags', bucket);
    Store.notify();
  }

  static async insertTrackPhoto(trackId: number, timeMs: number, filePath: string, note: string,
    latitude?: number, longitude?: number, altitude?: number, headingDeg?: number): Promise<void> {
    await Store.ready;
    const bucket: relationalStore.ValuesBucket = {
      'trackId': trackId,
      'timeMs': timeMs,
      'filePath': filePath,
      'note': note,
      'createdAt': Date.now()
    };
    Store.putOpt(bucket, 'latitude', latitude);
    Store.putOpt(bucket, 'longitude', longitude);
    Store.putOpt(bucket, 'altitude', altitude);
    Store.putOpt(bucket, 'headingDeg', headingDeg);
    await Store.rdb!.insert('track_photos', bucket);
    Store.notify();
  }

  static async deleteTrackTag(id: number): Promise<void> {
    await Store.ready;
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('track_tags');
    p.equalTo('id', id);
    await Store.rdb!.delete(p);
    Store.notify();
  }

  static async deleteTrackPhoto(id: number): Promise<void> {
    await Store.ready;
    // 删除沙箱文件
    try {
      const photos: TrackPhoto[] = await Store.listTrackPhotosAll(id);
      if (photos.length > 0 && Ctx.ui) {
        try {
          fs.unlinkSync(`${Ctx.ui.filesDir}/${photos[0].filePath}`);
        } catch (e) {
        }
      }
    } catch (e) {
    }
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('track_photos');
    p.equalTo('id', id);
    await Store.rdb!.delete(p);
    Store.notify();
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

  private static async listTrackPhotosAll(photoId: number): Promise<TrackPhoto[]> {
    const p: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('track_photos');
    p.equalTo('id', photoId);
    const rs: relationalStore.ResultSet = await Store.rdb!.query(p, ['filePath']);
    const out: TrackPhoto[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: photoId,
        trackId: 0,
        timeMs: 0,
        filePath: rs.getString(rs.getColumnIndex('filePath')),
        note: '',
        createdAt: 0
      });
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
