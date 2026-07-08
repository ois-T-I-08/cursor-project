/// レベル・突破のマスター設定（Web `level-config.ts` 相当）
library;

const levelMarks = [1, 20, 30, 40, 50, 60, 70, 80, 90];

List<int> get levelMarksList => List.unmodifiable(levelMarks);

const int levelMax = 90;
const int levelDisplayMax = 100;

List<int> get ascensionMarks =>
    levelMarks.where((m) => m > 1).toList(growable: false);

const expBooks = [
  (id: '104003', name: '大英雄の経験', exp: 20000),
  (id: '104002', name: '冒険家の経験', exp: 5000),
  (id: '104001', name: '流浪者の経験', exp: 1000),
];

const characterExpBetweenMarks = <String, int>{
  '1-20': 12275,
  '20-30': 57900,
  '30-40': 65700,
  '40-50': 39300,
  '50-60': 94800,
  '60-70': 114300,
  '70-80': 280800,
  '80-90': 393750,
};

const double weaponExpMultiplier = 1.5;

const int talentLevelMax = 10;
const int talentLevelDisplayMax = 13;

const talentMarks = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const talentFutureMarks = [11, 12, 13];
