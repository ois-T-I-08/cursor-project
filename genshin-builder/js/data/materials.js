// レベルアップに必要な経験書（簡易計算）
const EXP_PER_LEVEL = {
  20: 12000, 40: 45000, 50: 95000, 60: 170000, 70: 280000, 80: 430000, 90: 650000,
};

export function calcExpBooks(currentLevel, targetLevel) {
  if (currentLevel >= targetLevel) return { heroWit: 0, adventurer: 0, wanderer: 0, totalExp: 0 };

  let totalExp = 0;
  const thresholds = [20, 40, 50, 60, 70, 80, 90];

  for (let i = 0; i < thresholds.length; i++) {
    const lvl = thresholds[i];
    const prev = i === 0 ? 1 : thresholds[i - 1];
    if (targetLevel <= prev) break;
    if (currentLevel >= lvl) continue;

    const from = Math.max(currentLevel, prev);
    const to = Math.min(targetLevel, lvl);
    const ratio = (to - from) / (lvl - prev);
    totalExp += Math.ceil(EXP_PER_LEVEL[lvl] * ratio);
  }

  const heroWit = Math.ceil(totalExp / 20000);
  const wanderer = Math.ceil((totalExp % 20000) / 5000);
  const adventurer = Math.ceil(((totalExp % 20000) % 5000) / 1000);

  return { heroWit, adventurer, wanderer, totalExp, mora: Math.ceil(totalExp * 0.2) };
}

// 突破素材（簡易：地域別）
const ASCENSION_BY_REGION = {
  mondstadt: {
    gems: ['塞西莉亚の花', '蒲公英の種', '風車アスター'],
    boss: '飓风之种',
    local: '慕风蘑菇',
  },
  liyue: {
    gems: ['石珀', '霓裳花', '清心'],
    boss: '玄岩之塔',
    local: '琉璃百合',
  },
  inazuma: {
    gems: ['绯樱绣球', '鬼兜虫', '海灵芝'],
    boss: '恒常机關阵列',
    local: '天云草実',
  },
  sumeru: {
    gems: ['劫波莲', '月莲', '树王圣体菇'],
    boss: '兆载永劫龙兽',
    local: '帕蒂沙兰',
  },
  fontaine: {
    gems: ['虹彩蔷薇', '幽光星星', '湖光铃兰'],
    boss: '半永恒统辖矩阵',
    local: '初露之源',
  },
  natlan: {
    gems: ['灼灼彩菊', '青蜜梅', '肉龙掌'],
    boss: '秘源机兵·构型械',
    local: '灼灼彩菊',
  },
};

const ASCENSION_LEVELS = [20, 40, 50, 60, 70, 80, 90];

export function calcAscensionMaterials(character, currentLevel, targetLevel) {
  const region = ASCENSION_BY_REGION[character.region] || ASCENSION_BY_REGION.mondstadt;
  const materials = {
    mora: 0,
    gems: {},
    boss: 0,
    local: 0,
    specialty: 0,
  };

  for (const ascLevel of ASCENSION_LEVELS) {
    if (ascLevel <= currentLevel || ascLevel > targetLevel) continue;

    materials.mora += ascLevel <= 40 ? 20000 : ascLevel <= 60 ? 40000 : 60000;
    materials.boss += ascLevel <= 40 ? 3 : ascLevel <= 60 ? 6 : 9;
    materials.local += ascLevel <= 40 ? 10 : ascLevel <= 60 ? 20 : 30;

    const gemTier = ascLevel <= 40 ? 1 : ascLevel <= 60 ? 2 : 3;
    const gemName = region.gems[Math.min(gemTier - 1, region.gems.length - 1)];
    materials.gems[gemName] = (materials.gems[gemName] || 0) + (ascLevel <= 40 ? 3 : ascLevel <= 60 ? 6 : 9);
  }

  return { ...materials, bossName: region.boss, localName: region.local };
}

// 天賦素材
const TALENT_BOOKS = {
  mondstadt: ['「自由」の教導', '「自由」の導き', '「自由」の哲学'],
  liyue: ['「繁栄」の教導', '「繁栄」の導き', '「繁栄」の哲学'],
  inazuma: ['「浮世」の教導', '「浮世」の導き', '「浮世」の哲学'],
  sumeru: ['「創意」の教導', '「創意」の導き', '「創意」の哲学'],
  fontaine: ['「秩序」の教導', '「秩序」の導き', '「秩序」の哲学'],
  natlan: ['「焚燼」の教導', '「焚燼」の導き', '「焚燼」の哲学'],
};

const TALENT_COST = [
  { teach: 3, guide: 0, philo: 0, mora: 12500 },
  { teach: 2, guide: 0, philo: 0, mora: 17500 },
  { teach: 4, guide: 0, philo: 0, mora: 25000 },
  { teach: 6, guide: 0, philo: 0, mora: 30000 },
  { teach: 9, guide: 0, philo: 0, mora: 37500 },
  { teach: 4, guide: 4, philo: 0, mora: 120000 },
  { teach: 6, guide: 6, philo: 0, mora: 260000 },
  { teach: 12, guide: 9, philo: 0, mora: 450000 },
  { teach: 16, guide: 12, philo: 2, moro: 700000, crowns: 1 },
];

export function calcTalentMaterials(character, current, target) {
  if (current >= target) return null;

  const region = character.region || 'mondstadt';
  const books = TALENT_BOOKS[region] || TALENT_BOOKS.mondstadt;
  const result = {
    teach: 0,
    guide: 0,
    philo: 0,
    mora: 0,
    crowns: 0,
    weeklyBoss: 0,
    bookNames: books,
  };

  for (let lvl = current; lvl < target; lvl++) {
    const cost = TALENT_COST[lvl - 1];
    if (!cost) continue;
    result.teach += cost.teach || 0;
    result.guide += cost.guide || 0;
    result.philo += cost.philo || 0;
    result.mora += cost.mora || cost.moro || 0;
    result.crowns += cost.crowns || 0;
    result.weeklyBoss += (cost.guide || 0) + (cost.philo || 0) > 0 ? 1 : 0;
  }

  return result;
}

export function calcAllMaterials(character, options) {
  const { currentLevel, targetLevel, talents } = options;

  const exp = calcExpBooks(currentLevel, targetLevel);
  const ascension = calcAscensionMaterials(character, currentLevel, targetLevel);

  const talentResults = {};
  for (const [key, { current, target }] of Object.entries(talents)) {
    talentResults[key] = calcTalentMaterials(character, current, target);
  }

  let totalMora = exp.mora + ascension.mora;
  for (const t of Object.values(talentResults)) {
    if (t) totalMora += t.mora;
  }

  return { exp, ascension, talents: talentResults, totalMora };
}
