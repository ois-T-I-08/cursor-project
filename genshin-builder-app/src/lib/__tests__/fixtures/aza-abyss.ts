export function validAzaPayload(): Record<string, unknown> {
  return {
    retcode: 0,
    meta: {
      author: "aza.gg",
      api_ver: "5.6",
      updated_at: 1_784_430_000_418,
    },
    data: {
      updated_at: 1_784_430_000_418,
      schedule: {
        id: 121,
        start_time: 1_784_145_600,
        end_time: "1786823999",
      },
      sample_collection_progress: 0.668,
      sample_size: 0,
      sample_size_x_a: 1_111,
      sample_size_x_b: 2_000,
      character: {
        "10000125": {
          use_rate: 0.871,
          own_rate: 0.967,
          use_by_own_rate: 0.901,
          phase: { "1": 0.031 },
          constellations: [
            { id: "2", value: 0.187 },
            { id: "0", value: 0.658 },
          ],
          weapons: [{ id: "14522", value: 0.476 }],
          artifacts: [
            { set: { "15042": 4 }, value: 0.496 },
          ],
        },
      },
      party: {
        "1": [
          {
            id: "10000133,10000112,10000058,10000035",
            value: 0.207,
            use_rate: 0.207,
            own_rate: 0.548,
            use_by_own_rate: 0.377,
          },
        ],
        "2": [
          {
            id: "10000125,10000116,10000103,10000043",
            value: 0.101,
            use_rate: 0.101,
            own_rate: 0.62,
            use_by_own_rate: 0.163,
          },
        ],
      },
    },
  };
}
