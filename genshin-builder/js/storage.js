const STORAGE_KEY = 'genshin-builder-roster';

export function loadRoster() {
  try {
    const data = localStorage.getItem(STORAGE_KEY);
    return data ? JSON.parse(data) : [];
  } catch {
    return [];
  }
}

export function saveRoster(roster) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(roster));
}

export function createDefaultCharacter(charId) {
  return {
    id: `${charId}-${Date.now()}`,
    characterId: charId,
    level: 1,
    constellation: 0,
    talents: { na: 1, skill: 1, burst: 1 },
    weapon: { name: '', level: 1, refinement: 1 },
    artifacts: {
      flower: { set: 'なし', mainStat: 'HP', level: 0 },
      plume: { set: 'なし', mainStat: '攻撃力', level: 0 },
      sands: { set: 'なし', mainStat: '攻撃力%', level: 0 },
      goblet: { set: 'なし', mainStat: '元素ダメージ', level: 0 },
      circlet: { set: 'なし', mainStat: '会心率', level: 0 },
    },
    priority: false,
    notes: '',
    updatedAt: Date.now(),
  };
}

export function updateCharacter(roster, instanceId, updates) {
  return roster.map(c =>
    c.id === instanceId ? { ...c, ...updates, updatedAt: Date.now() } : c
  );
}

export function deleteCharacter(roster, instanceId) {
  return roster.filter(c => c.id !== instanceId);
}

export function getProgressPercent(char) {
  const levelScore = (char.level / 90) * 40;
  const talentScore = ((char.talents.na + char.talents.skill + char.talents.burst) / 30) * 30;
  const artifactScore = Object.values(char.artifacts).reduce((sum, a) => sum + (a.level / 20), 0) / 5 * 20;
  const weaponScore = (char.weapon.level / 90) * 10;
  return Math.min(100, Math.round(levelScore + talentScore + artifactScore + weaponScore));
}

export function isMaxLevel(char) {
  return char.level >= 90 &&
    char.talents.na >= 10 &&
    char.talents.skill >= 10 &&
    char.talents.burst >= 10;
}

export function isInProgress(char) {
  return !isMaxLevel(char) && char.level > 1;
}
