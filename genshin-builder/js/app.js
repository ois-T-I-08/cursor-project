import {
  CHARACTERS, ELEMENTS, WEAPONS, getCharacterById,
  ARTIFACT_SETS, ARTIFACT_SLOTS, ARTIFACT_SLOT_NAMES, MAIN_STATS,
} from './data/characters.js';
import { calcAllMaterials } from './data/materials.js';
import {
  loadRoster, saveRoster, createDefaultCharacter,
  updateCharacter, deleteCharacter, getProgressPercent, isMaxLevel, isInProgress,
} from './storage.js';

let roster = loadRoster();
let currentDetailId = null;

// DOM refs
const views = document.querySelectorAll('.view');
const navBtns = document.querySelectorAll('.nav-btn');
const modalAdd = document.getElementById('modal-add');
const modalDetail = document.getElementById('modal-detail');

function init() {
  bindNavigation();
  bindFilters();
  bindModals();
  bindCalculator();
  renderAll();
}

function bindNavigation() {
  navBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      const view = btn.dataset.view;
      navBtns.forEach(b => b.classList.toggle('active', b === btn));
      views.forEach(v => v.classList.toggle('active', v.id === `view-${view}`));
    });
  });
}

function bindFilters() {
  ['filter-element', 'filter-weapon', 'filter-rarity', 'filter-search'].forEach(id => {
    document.getElementById(id).addEventListener('input', renderRoster);
  });

  document.getElementById('btn-add-character').addEventListener('click', () => {
    renderAddList();
    modalAdd.showModal();
  });

  document.getElementById('add-search').addEventListener('input', renderAddList);
}

function bindModals() {
  document.querySelectorAll('[data-close]').forEach(btn => {
    btn.addEventListener('click', () => {
      btn.closest('dialog').close();
    });
  });

  modalAdd.addEventListener('click', e => {
    if (e.target === modalAdd) modalAdd.close();
  });
  modalDetail.addEventListener('click', e => {
    if (e.target === modalDetail) modalDetail.close();
  });
}

function bindCalculator() {
  const select = document.getElementById('calc-character');
  select.innerHTML = roster.map(r => {
    const c = getCharacterById(r.characterId);
    return `<option value="${r.id}">${c?.name || r.characterId}</option>`;
  }).join('') || '<option value="">キャラを追加してください</option>';

  select.addEventListener('change', () => {
    const entry = roster.find(r => r.id === select.value);
    if (!entry) return;
    document.getElementById('calc-current-level').value = entry.level;
    document.getElementById('calc-na-current').value = entry.talents.na;
    document.getElementById('calc-skill-current').value = entry.talents.skill;
    document.getElementById('calc-burst-current').value = entry.talents.burst;
  });

  document.getElementById('btn-calculate').addEventListener('click', runCalculation);

  if (roster.length > 0) {
    select.dispatchEvent(new Event('change'));
  }
}

function runCalculation() {
  const instanceId = document.getElementById('calc-character').value;
  const entry = roster.find(r => r.id === instanceId);
  if (!entry) return;

  const character = getCharacterById(entry.characterId);
  if (!character) return;

  const currentLevel = parseInt(document.getElementById('calc-current-level').value, 10);
  const targetLevel = parseInt(document.getElementById('calc-target-level').value, 10);

  const talents = {
    na: {
      current: parseInt(document.getElementById('calc-na-current').value, 10),
      target: parseInt(document.getElementById('calc-na-target').value, 10),
    },
    skill: {
      current: parseInt(document.getElementById('calc-skill-current').value, 10),
      target: parseInt(document.getElementById('calc-skill-target').value, 10),
    },
    burst: {
      current: parseInt(document.getElementById('calc-burst-current').value, 10),
      target: parseInt(document.getElementById('calc-burst-target').value, 10),
    },
  };

  const result = calcAllMaterials(character, { currentLevel, targetLevel, talents });
  renderCalcResults(result, character);
}

function renderCalcResults(result, character) {
  const container = document.getElementById('calc-results');
  const { exp, ascension, talents, totalMora } = result;

  let html = '';

  html += `<div class="material-section"><h3>モラ合計</h3>
    <div class="material-item"><span>モラ</span><span class="amount">${totalMora.toLocaleString()}</span></div></div>`;

  html += `<div class="material-section"><h3>経験書（Lv.${document.getElementById('calc-current-level').value} → ${document.getElementById('calc-target-level').value}）</h3>
    <div class="material-list">
      <div class="material-item"><span>大英雄の経験</span><span class="amount">${exp.heroWit}</span></div>
      <div class="material-item"><span>流浪者の経験</span><span class="amount">${exp.wanderer}</span></div>
      <div class="material-item"><span>冒険家の経験</span><span class="amount">${exp.adventurer}</span></div>
    </div></div>`;

  if (ascension.mora > 0) {
    html += `<div class="material-section"><h3>突破素材</h3><div class="material-list">`;
    for (const [gem, count] of Object.entries(ascension.gems)) {
      html += `<div class="material-item"><span>${gem}</span><span class="amount">${count}</span></div>`;
    }
    html += `<div class="material-item"><span>${ascension.bossName}</span><span class="amount">${ascension.boss}</span></div>`;
    html += `<div class="material-item"><span>${ascension.localName}</span><span class="amount">${ascension.local}</span></div>`;
    html += `</div></div>`;
  }

  const talentLabels = { na: '通常攻撃', skill: '元素スキル', burst: '元素爆発' };
  for (const [key, data] of Object.entries(talents)) {
    if (!data || (data.teach === 0 && data.guide === 0 && data.philo === 0)) continue;
    html += `<div class="material-section"><h3>天賦：${talentLabels[key]}</h3><div class="material-list">`;
    if (data.teach) html += `<div class="material-item"><span>${data.bookNames[0]}</span><span class="amount">${data.teach}</span></div>`;
    if (data.guide) html += `<div class="material-item"><span>${data.bookNames[1]}</span><span class="amount">${data.guide}</span></div>`;
    if (data.philo) html += `<div class="material-item"><span>${data.bookNames[2]}</span><span class="amount">${data.philo}</span></div>`;
    if (data.crowns) html += `<div class="material-item"><span>知恵の冠</span><span class="amount">${data.crowns}</span></div>`;
    html += `</div></div>`;
  }

  container.innerHTML = html;
}

function renderAll() {
  renderDashboard();
  renderRoster();
  bindCalculator();
}

function renderDashboard() {
  document.getElementById('stat-total').textContent = roster.length;
  document.getElementById('stat-max-level').textContent = roster.filter(isMaxLevel).length;
  document.getElementById('stat-in-progress').textContent = roster.filter(isInProgress).length;
  document.getElementById('stat-priority').textContent = roster.filter(c => c.priority).length;

  const priorityList = document.getElementById('priority-list');
  const priorities = roster.filter(c => c.priority);
  if (priorities.length === 0) {
    priorityList.innerHTML = '<p class="empty-state">優先キャラを設定するとここに表示されます</p>';
  } else {
    priorityList.innerHTML = priorities.map(renderPriorityItem).join('');
    priorityList.querySelectorAll('.priority-item').forEach(el => {
      el.addEventListener('click', () => openDetail(el.dataset.id));
    });
  }

  const recentList = document.getElementById('recent-list');
  const recent = [...roster].sort((a, b) => b.updatedAt - a.updatedAt).slice(0, 6);
  if (recent.length === 0) {
    recentList.innerHTML = '<p class="empty-state">キャラを追加して育成管理を始めましょう</p>';
  } else {
    recentList.innerHTML = recent.map(renderCharacterCard).join('');
    bindCardClicks(recentList);
  }
}

function renderRoster() {
  const element = document.getElementById('filter-element').value;
  const weapon = document.getElementById('filter-weapon').value;
  const rarity = document.getElementById('filter-rarity').value;
  const search = document.getElementById('filter-search').value.toLowerCase();

  const filtered = roster.filter(r => {
    const c = getCharacterById(r.characterId);
    if (!c) return false;
    if (element && c.element !== element) return false;
    if (weapon && c.weapon !== weapon) return false;
    if (rarity && c.rarity !== parseInt(rarity, 10)) return false;
    if (search && !c.name.toLowerCase().includes(search)) return false;
    return true;
  });

  const grid = document.getElementById('roster-grid');
  if (filtered.length === 0) {
    grid.innerHTML = '<p class="empty-state">該当するキャラがいません。「+ キャラ追加」から登録してください</p>';
  } else {
    grid.innerHTML = filtered.map(renderCharacterCard).join('');
    bindCardClicks(grid);
  }
}

function renderCharacterCard(entry) {
  const c = getCharacterById(entry.characterId);
  if (!c) return '';
  const el = ELEMENTS[c.element];
  const progress = getProgressPercent(entry);

  return `
    <div class="character-card ${entry.priority ? 'priority' : ''}" data-id="${entry.id}"
         style="--element-color: ${el.color}">
      <div class="char-avatar">${c.emoji}</div>
      <div class="char-name">${c.name}</div>
      <div class="char-meta">${el.name} · ${WEAPONS[c.weapon].name} · ★${c.rarity}</div>
      <div class="char-level">Lv.${entry.level} / C${entry.constellation}</div>
      <div class="progress-bar"><div class="progress-fill" style="width: ${progress}%"></div></div>
    </div>`;
}

function renderPriorityItem(entry) {
  const c = getCharacterById(entry.characterId);
  if (!c) return '';
  const el = ELEMENTS[c.element];
  const progress = getProgressPercent(entry);

  return `
    <div class="priority-item" data-id="${entry.id}">
      <div class="char-avatar" style="--element-color: ${el.color}; border-color: ${el.color}">${c.emoji}</div>
      <div class="priority-info">
        <h3>${c.name}</h3>
        <p>Lv.${entry.level} · 天賦 ${entry.talents.na}/${entry.talents.skill}/${entry.talents.burst} · 進捗 ${progress}%</p>
      </div>
    </div>`;
}

function bindCardClicks(container) {
  container.querySelectorAll('.character-card').forEach(card => {
    card.addEventListener('click', () => openDetail(card.dataset.id));
  });
}

function renderAddList() {
  const search = document.getElementById('add-search').value.toLowerCase();
  const owned = new Set(roster.map(r => r.characterId));
  const list = document.getElementById('add-character-list');

  const filtered = CHARACTERS.filter(c => {
    if (search && !c.name.toLowerCase().includes(search)) return false;
    return true;
  });

  list.innerHTML = filtered.map(c => {
    const el = ELEMENTS[c.element];
    const disabled = owned.has(c.id);
    return `
      <div class="add-char-item ${disabled ? 'disabled' : ''}" data-char-id="${c.id}"
           style="--element-color: ${el.color}">
        <div class="char-avatar">${c.emoji}</div>
        <div class="char-name">${c.name}</div>
      </div>`;
  }).join('');

  list.querySelectorAll('.add-char-item:not(.disabled)').forEach(item => {
    item.addEventListener('click', () => {
      addCharacter(item.dataset.charId);
    });
  });
}

function addCharacter(charId) {
  const newChar = createDefaultCharacter(charId);
  roster = [...roster, newChar];
  saveRoster(roster);
  modalAdd.close();
  renderAll();
  openDetail(newChar.id);
}

function openDetail(instanceId) {
  currentDetailId = instanceId;
  const entry = roster.find(r => r.id === instanceId);
  if (!entry) return;

  const c = getCharacterById(entry.characterId);
  if (!c) return;

  const el = ELEMENTS[c.element];
  document.getElementById('detail-name').textContent = c.name;

  document.getElementById('detail-body').innerHTML = `
    <div class="detail-header">
      <div class="detail-avatar" style="--element-color: ${el.color}; border-color: ${el.color}">${c.emoji}</div>
      <div class="detail-info">
        <h3>${el.name} · ${WEAPONS[c.weapon].name} · ★${c.rarity}</h3>
        <div class="badges">
          <span class="badge" style="--element-color: ${el.color}">${el.name}</span>
          <span class="badge">${WEAPONS[c.weapon].name}</span>
          <span class="badge">進捗 ${getProgressPercent(entry)}%</span>
        </div>
      </div>
    </div>

    <div class="detail-section">
      <h4>基本ステータス</h4>
      <div class="form-row">
        <div class="form-group">
          <label>レベル</label>
          <input type="number" id="edit-level" min="1" max="90" value="${entry.level}" />
        </div>
        <div class="form-group">
          <label>命ノ星</label>
          <input type="number" id="edit-constellation" min="0" max="6" value="${entry.constellation}" />
        </div>
      </div>
      <label class="checkbox-label">
        <input type="checkbox" id="edit-priority" ${entry.priority ? 'checked' : ''} />
        優先育成キャラ
      </label>
    </div>

    <div class="detail-section">
      <h4>天賦</h4>
      <div class="form-row">
        <div class="form-group">
          <label>通常攻撃</label>
          <input type="number" id="edit-na" min="1" max="10" value="${entry.talents.na}" />
        </div>
        <div class="form-group">
          <label>元素スキル</label>
          <input type="number" id="edit-skill" min="1" max="10" value="${entry.talents.skill}" />
        </div>
        <div class="form-group">
          <label>元素爆発</label>
          <input type="number" id="edit-burst" min="1" max="10" value="${entry.talents.burst}" />
        </div>
      </div>
    </div>

    <div class="detail-section">
      <h4>武器</h4>
      <div class="form-row">
        <div class="form-group">
          <label>武器名</label>
          <input type="text" id="edit-weapon-name" value="${entry.weapon.name}" placeholder="例：天空の刃" />
        </div>
        <div class="form-group">
          <label>レベル</label>
          <input type="number" id="edit-weapon-level" min="1" max="90" value="${entry.weapon.level}" />
        </div>
        <div class="form-group">
          <label>精錬</label>
          <input type="number" id="edit-weapon-refinement" min="1" max="5" value="${entry.weapon.refinement}" />
        </div>
      </div>
    </div>

    <div class="detail-section">
      <h4>聖遺物</h4>
      <div class="artifact-grid">
        ${ARTIFACT_SLOTS.map(slot => renderArtifactSlot(slot, entry.artifacts[slot])).join('')}
      </div>
    </div>

    <div class="detail-section">
      <h4>メモ</h4>
      <textarea id="edit-notes" rows="3" placeholder="ビルド方針や欲しいステータスなど">${entry.notes}</textarea>
    </div>

    <div class="detail-actions">
      <button class="btn btn-primary" id="btn-save">保存</button>
      <button class="btn btn-secondary" id="btn-calc-this">素材計算</button>
      <button class="btn btn-danger btn-sm" id="btn-delete">削除</button>
    </div>`;

  document.getElementById('btn-save').addEventListener('click', saveDetail);
  document.getElementById('btn-delete').addEventListener('click', deleteDetail);
  document.getElementById('btn-calc-this').addEventListener('click', () => {
    modalDetail.close();
    navBtns.forEach(b => b.classList.toggle('active', b.dataset.view === 'materials'));
    views.forEach(v => v.classList.toggle('active', v.id === 'view-materials'));
    document.getElementById('calc-character').value = instanceId;
    document.getElementById('calc-character').dispatchEvent(new Event('change'));
  });

  modalDetail.showModal();
}

function renderArtifactSlot(slot, data) {
  const sets = ARTIFACT_SETS.map(s => `<option ${data.set === s ? 'selected' : ''}>${s}</option>`).join('');
  const stats = (MAIN_STATS[slot] || []).map(s => `<option ${data.mainStat === s ? 'selected' : ''}>${s}</option>`).join('');

  return `
    <div class="artifact-slot">
      <label>${ARTIFACT_SLOT_NAMES[slot]}</label>
      <select data-artifact-set="${slot}">${sets}</select>
      <select data-artifact-stat="${slot}">${stats}</select>
      <input type="number" data-artifact-level="${slot}" min="0" max="20" value="${data.level}" placeholder="Lv" />
    </div>`;
}

function saveDetail() {
  const artifacts = {};
  ARTIFACT_SLOTS.forEach(slot => {
    artifacts[slot] = {
      set: document.querySelector(`[data-artifact-set="${slot}"]`).value,
      mainStat: document.querySelector(`[data-artifact-stat="${slot}"]`).value,
      level: parseInt(document.querySelector(`[data-artifact-level="${slot}"]`).value, 10) || 0,
    };
  });

  roster = updateCharacter(roster, currentDetailId, {
    level: parseInt(document.getElementById('edit-level').value, 10),
    constellation: parseInt(document.getElementById('edit-constellation').value, 10),
    priority: document.getElementById('edit-priority').checked,
    talents: {
      na: parseInt(document.getElementById('edit-na').value, 10),
      skill: parseInt(document.getElementById('edit-skill').value, 10),
      burst: parseInt(document.getElementById('edit-burst').value, 10),
    },
    weapon: {
      name: document.getElementById('edit-weapon-name').value,
      level: parseInt(document.getElementById('edit-weapon-level').value, 10),
      refinement: parseInt(document.getElementById('edit-weapon-refinement').value, 10),
    },
    artifacts,
    notes: document.getElementById('edit-notes').value,
  });

  saveRoster(roster);
  modalDetail.close();
  renderAll();
}

function deleteDetail() {
  if (!confirm('このキャラを削除しますか？')) return;
  roster = deleteCharacter(roster, currentDetailId);
  saveRoster(roster);
  modalDetail.close();
  renderAll();
}

init();
