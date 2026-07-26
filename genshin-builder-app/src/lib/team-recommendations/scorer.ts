import type { InputQuality, SimulationBuildSnapshot, TeamCandidate, TeamRecommendationRequest } from "./types";

export interface ScoreWeights {
  observed: number;
  build: number;
  stability: number;
  energy: number;
  accessibility: number;
}

const DEFAULT_WEIGHTS: ScoreWeights = {
  observed: 0.35,
  build: 0.25,
  stability: 0.15,
  energy: 0.1,
  accessibility: 0.15,
};

export class TeamRecommendationScorer {
  constructor(private readonly weights = readWeights()) {}

  score(input: { candidate: TeamCandidate; request: TeamRecommendationRequest }): number {
    const members = input.request.characters.filter((character) => input.candidate.members.includes(character.characterId));
    const observed = Math.min(1, input.candidate.azaUsageRate * 10 + (input.candidate.observedByAza ? 0.35 : 0));
    const build = members.reduce((sum, member) => sum + buildScore(member), 0) / 4;
    const accessibility = members.reduce((sum, member) => sum + (member.isOwned ? 1 : 0) + (member.rarity === 4 ? 0.3 : 0), 0) / 5.2;
    const preferenceBonus = input.request.preference === "stability"
      ? (input.candidate.hasSustain ? 0.04 : 0) + input.candidate.energyStability * 0.01
      : input.request.preference === "fourStar"
        ? members.filter((member) => member.rarity === 4).length * 0.01
        : input.request.preference === "built"
          ? build * 0.05
          : observed * 0.05;
    const raw = observed * this.weights.observed + build * this.weights.build
      + (input.candidate.hasSustain ? 1 : 0.35) * this.weights.stability
      + input.candidate.energyStability * this.weights.energy
      + Math.min(1, accessibility) * this.weights.accessibility
      + preferenceBonus;
    return Math.round(Math.max(0, Math.min(1, raw)) * 1000) / 1000;
  }
}

export function worstInputQuality(builds: SimulationBuildSnapshot[]): InputQuality {
  const order: InputQuality[] = ["exact", "partial", "defaulted", "unsupported"];
  return builds.reduce<InputQuality>((worst, build) => order.indexOf(build.inputQuality) > order.indexOf(worst) ? build.inputQuality : worst, "exact");
}

function buildScore(build: SimulationBuildSnapshot): number {
  const quality = { exact: 1, partial: 0.75, defaulted: 0.5, unsupported: 0.2 }[build.inputQuality];
  return Math.min(1, (build.level / 90) * 0.55 + (build.weapon?.level ?? 0) / 90 * 0.25 + quality * 0.2);
}

function readWeights(env: NodeJS.ProcessEnv = process.env): ScoreWeights {
  const names: Array<keyof ScoreWeights> = ["observed", "build", "stability", "energy", "accessibility"];
  const parsed = Object.fromEntries(
    names.map((name) => [name, Number(env[`TEAM_RECOMMENDATION_SCORE_${name.toUpperCase()}`])]),
  ) as unknown as ScoreWeights;
  return names.every((name) => Number.isFinite(parsed[name]) && parsed[name] >= 0)
    && Math.abs(names.reduce((sum, name) => sum + parsed[name], 0) - 1) < 0.001
    ? parsed
    : DEFAULT_WEIGHTS;
}
