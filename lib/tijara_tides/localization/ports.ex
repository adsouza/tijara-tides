defmodule TijaraTides.Localization.Ports do
  @moduledoc "Display translations for the static port catalogue; persisted identifiers remain unchanged."
  use Gettext, backend: TijaraTides.Localization.Backend
  def translate("Abu Dhabi"), do: gettext("Abu Dhabi")
  def translate("Khalifa Port"), do: gettext("Khalifa Port")

  def translate(
        "Crude and refined fuel exporter with large aluminium smelting that consumes imported scrap. Buys power-generation turbines and all of its food."
      ),
      do:
        gettext(
          "Crude and refined fuel exporter with large aluminium smelting that consumes imported scrap. Buys power-generation turbines and all of its food."
        )

  def translate("Antwerp"), do: gettext("Antwerp")

  def translate(
        "Chemicals, refining and Europe's diamond trade, with major reefer capacity and a construction-machinery export stream. Ships refined products and recovered plastics outbound, and its inland catchment reaches Italian and French fashion houses."
      ),
      do:
        gettext(
          "Chemicals, refining and Europe's diamond trade, with major reefer capacity and a construction-machinery export stream. Ships refined products and recovered plastics outbound, and its inland catchment reaches Italian and French fashion houses."
        )

  def translate("Athens"), do: gettext("Athens")
  def translate("Piraeus"), do: gettext("Piraeus")

  def translate(
        "Greek refining, ore mining and aluminium production alongside Mediterranean transshipment. Exports fuel, ore, metal scrap and fruit; imports grain and meat."
      ),
      do:
        gettext(
          "Greek refining, ore mining and aluminium production alongside Mediterranean transshipment. Exports fuel, ore, metal scrap and fruit; imports grain and meat."
        )

  def translate("Busan"), do: gettext("Busan")

  def translate(
        "Korea's industrial gateway: steel, shipbuilding, heavy turbines and consumer electronics, fed by imported ore and crude. Exports refined fuel and the catch of a large distant-water fishing fleet."
      ),
      do:
        gettext(
          "Korea's industrial gateway: steel, shipbuilding, heavy turbines and consumer electronics, fed by imported ore and crude. Exports refined fuel and the catch of a large distant-water fishing fleet."
        )

  def translate("Colombo"), do: gettext("Colombo")

  def translate(
        "South Asian transshipment point and the roster's cinnamon source, exporting spices, apparel, gemstones and seafood. Small hinterland, so most bulk arrives rather than departs."
      ),
      do:
        gettext(
          "South Asian transshipment point and the roster's cinnamon source, exporting spices, apparel, gemstones and seafood. Small hinterland, so most bulk arrives rather than departs."
        )

  def translate("Colón"), do: gettext("Colón")
  def translate("Manzanillo"), do: gettext("Manzanillo")

  def translate(
        "Canal-side transshipment and the Colón Free Zone's re-export trade into Latin America, plus Central American bananas."
      ),
      do:
        gettext(
          "Canal-side transshipment and the Colón Free Zone's re-export trade into Latin America, plus Central American bananas."
        )

  def translate("Dubai"), do: gettext("Dubai")
  def translate("Jebel Ali"), do: gettext("Jebel Ali")

  def translate(
        "Re-export hub for consumer goods and gold across the Gulf and East Africa, with sustained construction demand and no food production."
      ),
      do:
        gettext(
          "Re-export hub for consumer goods and gold across the Gulf and East Africa, with sustained construction demand and no food production."
        )

  def translate("Guangzhou"), do: gettext("Guangzhou")
  def translate("Nansha"), do: gettext("Nansha")

  def translate(
        "The delta's heavy and household manufacturing arm: appliances, apparel, construction and agricultural machinery, and a large grain-consuming population."
      ),
      do:
        gettext(
          "The delta's heavy and household manufacturing arm: appliances, apparel, construction and agricultural machinery, and a large grain-consuming population."
        )

  def translate("Hamburg"), do: gettext("Hamburg")

  def translate(
        "German and Central European machinery export — turbines, construction and agricultural equipment — plus grain, meat and aluminium scrap outbound to Asia. Europe's largest copper smelter sits here and consumes imported copper scrap. Its inland catchment also carries Central European fashion houses and sawmill lumber."
      ),
      do:
        gettext(
          "German and Central European machinery export — turbines, construction and agricultural equipment — plus grain, meat and aluminium scrap outbound to Asia. Europe's largest copper smelter sits here and consumes imported copper scrap. Its inland catchment also carries Central European fashion houses and sawmill lumber."
        )

  def translate("Ho Chi Minh City"), do: gettext("Ho Chi Minh City")
  def translate("Saigon and Cai Mep"), do: gettext("Saigon and Cai Mep")

  def translate(
        "Vietnam's export engine for apparel, electronics, rice, fruit, pepper and farmed seafood. Takes in refined fuel and recovered plastics for processing."
      ),
      do:
        gettext(
          "Vietnam's export engine for apparel, electronics, rice, fruit, pepper and farmed seafood. Takes in refined fuel and recovered plastics for processing."
        )

  def translate("Hong Kong"), do: gettext("Hong Kong")

  def translate(
        "Transshipment, finance and luxury retail with no manufacturing base. The roster's largest re-exporter of jewelry and rare whisky, and the centre of its collector auction trade, importing essentially all of its food."
      ),
      do:
        gettext(
          "Transshipment, finance and luxury retail with no manufacturing base. The roster's largest re-exporter of jewelry and rare whisky, and the centre of its collector auction trade, importing essentially all of its food."
        )

  def translate("Houston"), do: gettext("Houston")
  def translate("Bayport"), do: gettext("Bayport")

  def translate(
        "US Gulf energy and agriculture: crude, refined fuel, grain, beef, heavy machinery, Kentucky whiskey and the roster's broadest scrap and recovered-plastics export. Regional sawmills add lumber to its outbound cargoes. Channel draft excludes the largest ships."
      ),
      do:
        gettext(
          "US Gulf energy and agriculture: crude, refined fuel, grain, beef, heavy machinery, Kentucky whiskey and the roster's broadest scrap and recovered-plastics export. Regional sawmills add lumber to its outbound cargoes. Channel draft excludes the largest ships."
        )

  def translate("Jakarta"), do: gettext("Jakarta")
  def translate("Tanjung Priok"), do: gettext("Tanjung Priok")

  def translate(
        "Indonesian resource exporter and fast-growing consumer market, importing grain and fuel while shipping ore, palm oil, the nutmeg and cloves of the original Spice Islands, apparel and seafood. Its regional sawmills also supply lumber."
      ),
      do:
        gettext(
          "Indonesian resource exporter and fast-growing consumer market, importing grain and fuel while shipping ore, palm oil, the nutmeg and cloves of the original Spice Islands, apparel and seafood. Its regional sawmills also supply lumber."
        )

  def translate("Los Angeles"), do: gettext("Los Angeles")
  def translate("San Pedro Bay"), do: gettext("San Pedro Bay")

  def translate(
        "The largest US import gateway for consumer goods, balanced by Californian produce, beef and the roster's heaviest scrap export. Congestion-prone and expensive."
      ),
      do:
        gettext(
          "The largest US import gateway for consumer goods, balanced by Californian produce, beef and the roster's heaviest scrap export. Congestion-prone and expensive."
        )

  def translate("Manila"), do: gettext("Manila")

  def translate(
        "Philippine semiconductor assembly, nickel and iron ore mining, and tropical agriculture. The roster's leading fruit, tuna and coconut oil exporter, dependent on imported grain, fuel and meat."
      ),
      do:
        gettext(
          "Philippine semiconductor assembly, nickel and iron ore mining, and tropical agriculture. The roster's leading fruit, tuna and coconut oil exporter, dependent on imported grain, fuel and meat."
        )

  def translate("Mumbai"), do: gettext("Mumbai")
  def translate("Jawaharlal Nehru / Nhava Sheva"), do: gettext("Jawaharlal Nehru / Nhava Sheva")

  def translate(
        "India's largest container gateway: ore, refined fuel, tractors, apparel and spices out, crude in, and the roster's dominant cut-gemstone and jewelry exporter. A heavy scrap buyer."
      ),
      do:
        gettext(
          "India's largest container gateway: ore, refined fuel, tractors, apparel and spices out, crude in, and the roster's dominant cut-gemstone and jewelry exporter. A heavy scrap buyer."
        )

  def translate("New York City"), do: gettext("New York City")
  def translate("Port Newark–Elizabeth"), do: gettext("Port Newark–Elizabeth")

  def translate(
        "The US Northeast's consumer gateway and a luxury market in its own right, exporting scrap, meat and American whiskey while importing finished goods and fuel."
      ),
      do:
        gettext(
          "The US Northeast's consumer gateway and a luxury market in its own right, exporting scrap, meat and American whiskey while importing finished goods and fuel."
        )

  def translate("Rotterdam"), do: gettext("Rotterdam")

  def translate(
        "Europe's largest port and its oil gateway, feeding Rhine-valley steel and engineering. Exports refined fuel, turbines and scrap and lands enormous volumes of fruit."
      ),
      do:
        gettext(
          "Europe's largest port and its oil gateway, feeding Rhine-valley steel and engineering. Exports refined fuel, turbines and scrap and lands enormous volumes of fruit."
        )

  def translate("Shanghai"), do: gettext("Shanghai")
  def translate("Waigaoqiao and Yangshan"), do: gettext("Waigaoqiao and Yangshan")

  def translate(
        "China's largest gateway, serving the Yangtze Delta's steel, machinery and electronics industries. Ore and crude in, finished manufactures out, with a wealthy consumer market of its own."
      ),
      do:
        gettext(
          "China's largest gateway, serving the Yangtze Delta's steel, machinery and electronics industries. Ore and crude in, finished manufactures out, with a wealthy consumer market of its own."
        )

  def translate("Shenzhen"), do: gettext("Shenzhen")
  def translate("Yantian"), do: gettext("Yantian")

  def translate(
        "Electronics manufacturing capital of the Pearl River Delta. Draws copper and components in, ships finished devices out."
      ),
      do:
        gettext(
          "Electronics manufacturing capital of the Pearl River Delta. Draws copper and components in, ships finished devices out."
        )

  def translate("Singapore"), do: gettext("Singapore")

  def translate(
        "Transshipment and refining hub with almost no primary hinterland. Buys crude to sell refined fuel, re-exports spirits across the region, and imports nearly all of its food."
      ),
      do:
        gettext(
          "Transshipment and refining hub with almost no primary hinterland. Buys crude to sell refined fuel, re-exports spirits across the region, and imports nearly all of its food."
        )

  def translate("São Paulo"), do: gettext("São Paulo")
  def translate("Santos"), do: gettext("Santos")

  def translate(
        "Brazil's agricultural and mineral outlet: soy and soy oil, iron ore, crude, citrus and the roster's largest meat export, against imported fuel and manufactures. Regional sawmills supply lumber for export."
      ),
      do:
        gettext(
          "Brazil's agricultural and mineral outlet: soy and soy oil, iron ore, crude, citrus and the roster's largest meat export, against imported fuel and manufactures. Regional sawmills supply lumber for export."
        )

  def translate("Tangier"), do: gettext("Tangier")
  def translate("Tanger Med"), do: gettext("Tanger Med")

  def translate(
        "Low-cost North African transshipment and light manufacturing: apparel, electronics assembly, citrus and sardines, against imported grain and fuel."
      ),
      do:
        gettext(
          "Low-cost North African transshipment and light manufacturing: apparel, electronics assembly, citrus and sardines, against imported grain and fuel."
        )

  def translate("Tokyo"), do: gettext("Tokyo")

  def translate(
        "High-value Japanese manufacturing — construction and agricultural machinery, turbines, electronics — alongside the roster's foremost whisky distilling and the world's largest appetite for imported seafood."
      ),
      do:
        gettext(
          "High-value Japanese manufacturing — construction and agricultural machinery, turbines, electronics — alongside the roster's foremost whisky distilling and the world's largest appetite for imported seafood."
        )

  def translate("Valencia"), do: gettext("Valencia")

  def translate(
        "Spanish Mediterranean exporter of citrus, pork, appliances and apparel, and of construction and agricultural machinery, with strong reefer capacity and moderate costs."
      ),
      do:
        gettext(
          "Spanish Mediterranean exporter of citrus, pork, appliances and apparel, and of construction and agricultural machinery, with strong reefer capacity and moderate costs."
        )

  def translate(value), do: TijaraTides.Localization.text(value)
end
