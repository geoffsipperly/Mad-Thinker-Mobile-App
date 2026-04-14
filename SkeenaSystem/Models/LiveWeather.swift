// Bend Fly Shop
// Shared weather snapshot used by all landing views.

import Foundation

struct LiveWeather {
  let locationName: String
  let condition: String
  let icon: String
  let temp: Int
  let windDir: String
  let windSpeed: Int
  let pressureVal: Int
  let pressureTrend: WeatherPressureTrend
  struct HourlySlot: Identifiable {
    var id: String { hour }
    let hour: String
    let icon: String
    let temp: Int
    let precipChance: Int
  }
  let hourly: [HourlySlot]
  /// Backend weather provider: "open-meteo" or "weatherapi". Informational.
  let source: String?
}
