import { getAbyssStatisticsService } from "@/lib/abyss/statistics-service";
import { TeamRecommendationService } from "./service";
import { readTeamRecommendationSettings } from "./settings";
import { PrismaSimulationStore } from "./store";

let service: TeamRecommendationService | undefined;
export function getTeamRecommendationService(): TeamRecommendationService {
  if (!service) {
    const settings = readTeamRecommendationSettings();
    service = new TeamRecommendationService(
      new PrismaSimulationStore(),
      () => getAbyssStatisticsService().load(),
      settings,
    );
  }
  return service;
}
