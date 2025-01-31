defmodule MapLibre do
  @moduledoc """
  Elixir bindings to [MapLibre Style
  Specification](https://maplibre.org/maplibre-gl-js-docs/style-spec/).

  A MapLibre style is a document that defines the visual appearance of a map: what data to draw,
  the order to draw it in, and how to style the data when drawing it. A style document is a JSON
  object with specific root level and nested properties. To learn more about the style
  specification and its properties, please see the
  [documentation](https://maplibre.org/maplibre-gl-js-docs/style-spec/)

  ## Composing maps

  Laying out a basic MapLibre map consists of the following steps:

      alias MapLibre, as: Ml

      # Initialize the specification with the initial style and optionally some other root properties.
      # If you don't provide a initial style, the default style will be loaded for you
      Ml.new(center: {-74.5, 40}, zoom: 6)

      # Add sources to make their data available
      |> Ml.add_source("rwanda-provinces",
          type: :geojson,
          data: "https://maplibre.org/maplibre-gl-js-docs/assets/rwanda-provinces.geojson"
      )

      # Add layers and refer them to sources to define their visual representation and make them visible
      |> Ml.add_layer(id: "rwanda-provinces",
          type: :fill,
          source: "rwanda-provinces",
          paint: [fill_color: "#4A9661"]
      )

  ## Expressions

  Expressions are extremely powerful and useful to render complex data. To use them just ensure
  that you pass valid expressions following the rules and syntax of the [official
  documentation](https://maplibre.org/maplibre-gl-js-docs/style-spec/expressions/)

  ## Options

  To provide a more Elixir-friendly experience, the options are automatically normalized, so you
  can use keyword lists and snake-case atom keys.
  """

  alias MapLibre.Utils

  @default_style "https://demotiles.maplibre.org/style.json"
  @to_kebab Utils.kebab_case_properties()

  defstruct spec: %{}

  @type t() :: %__MODULE__{spec: spec()}

  @type spec :: map()

  @doc """
  Returns a style specification wrapped in the `MapLibre` struct. If you don't provide a initial
  style, the [default style](https://demotiles.maplibre.org/style.json) will be loaded for you. If
  you wish to build a new style completely from scratch, pass an empty map `%{}` as `:style`
  option. The style specification version will be automatically set to 8.

  ## Options

  Only the following properties are allowed directly on `new/1`

    * `:bearing` -  Default bearing, in degrees. The bearing is the compass direction that is
      "up"; for example, a bearing of 90° orients the map so that east is up. This value will be
      used only if the map has not been positioned by other means (e.g. map options or user
      interaction). Default: 0

    * `:center` - Default map center in longitude and latitude. The style center will be used only
      if the map has not been positioned by other means (e.g. map options or user interaction).
      Default: {0, 0}

    * `:name` - A human-readable name for the style.

    * `:pitch` - Default pitch, in degrees. Zero is perpendicular to the surface, for a look
      straight down at the map, while a greater value like 60 looks ahead towards the horizon. The
      style pitch will be used only if the map has not been positioned by other means (e.g. map
      options or user interaction). Default: 0

    * `:zoom` - Default zoom level. The style zoom will be used only if the map has not been
      positioned by other means (e.g. map options or user interaction).

    * `:style` - The initial style specification. Default:
      "https://demotiles.maplibre.org/style.json"

  To manipulate any other [style root
  properties](https://maplibre.org/maplibre-gl-js-docs/style-spec/root/), use the
  corresponding functions

  ## Examples

      Ml.new(
        center: {-74.5, 40},
        zoom: 9,
        name: "Rwanda population density"
      )
      |> ...

  See [the docs](https://maplibre.org/maplibre-gl-js-docs/style-spec/) for more details.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    validade_new_opts!(opts)
    style = opts |> Keyword.get(:style, @default_style) |> to_style()
    ml = %MapLibre{spec: style}
    ml_props = opts |> Keyword.delete(:style) |> opts_to_ml_props()
    update_in(ml.spec, fn spec -> Map.merge(spec, ml_props) end)
  end

  defp validade_new_opts!(opts) do
    new_options = [:bearing, :center, :name, :pitch, :zoom, :style]
    options = new_options |> Enum.map_join(", ", &inspect/1)

    for {option, _value} <- opts do
      if option not in new_options do
        raise ArgumentError,
              "unknown option, expected one of #{options}, got: #{inspect(option)}"
      end
    end
  end

  @doc """
  Returns the underlying MapLibre specification. The result is a nested Elixir data structure that
  serializes to MapLibre style JSON specification.

  See [the docs](https://maplibre.org/maplibre-gl-js-docs/style-spec/) for more details.
  """
  @spec to_spec(t()) :: spec()
  def to_spec(ml) do
    ml.spec
  end

  @doc """
  Adds a data source to the sources in the specification.

  Sources state which data the map should display. Specify the type of source with the `:type`
  property, which must be one of `:vector`, `:raster`, `:raster_dem`, `:geojson`, `:image` or `:video`.

  ## Examples

      |> Ml.add_source("rwanda-provinces",
            type: :geojson,
            data: "https://maplibre.org/maplibre-gl-js-docs/assets/rwanda-provinces.geojson"
      )

  See [the docs](https://maplibre.org/maplibre-gl-js-docs/style-spec/sources/) for more details.
  """
  @spec add_source(t(), String.t(), keyword()) :: t()
  def add_source(ml, source, opts \\ []) do
    validate_source!(opts)
    source = %{source => opts_to_ml_props(opts)}
    sources = Map.merge(ml.spec["sources"], source)
    update_in(ml.spec, fn spec -> Map.put(spec, "sources", sources) end)
  end

  defp validate_source!(opts) do
    type = opts[:type]

    validate_source_type!(type)
    if type == :geojson, do: validate_geojson!(opts)
  end

  defp validate_source_type!(nil) do
    raise ArgumentError,
          "source type is required"
  end

  defp validate_source_type!(type) do
    source_types = [:vector, :raster, :raster_dem, :geojson, :image, :video]

    if type not in source_types do
      types = source_types |> Enum.map_join(", ", &inspect/1)

      raise ArgumentError,
            "unknown source type, expected one of #{types}, got: #{inspect(type)}"
    end
  end

  defp validate_geojson!(opts) do
    data = opts[:data]

    if is_nil(data) || data == [] do
      raise ArgumentError,
            ~s(The GeoJSON data must be given using the "data" property, whose value can be a URL or inline GeoJSON.)
    end
  end

  @doc """
  Adds a layer to the layers list in the specification.

  A style's layers property lists all the layers available in the style. The type of layer is
  specified by the `:type` property, and must be one of `:background`, `:fill`, `:line`,
  `:symbol`, `:raster`, `:circle`, `:fill_extrusion`, `:heatmap`, `:hillshade`.

  Except for layers of the `:background` type, each layer needs to refer to a source. Layers take
  the data that they get from a source, optionally filter features, and then define how those
  features are styled.

  ## Required

    * `:id` - Unique layer name.

    * `:type` - One of:

      * `:fill` -  A filled polygon with an optional stroked border.
      * `:line` -  A stroked line.
      * `:symbol` - An icon or a text label. "circle": A filled circle.
      * `:heatmap` - A heatmap.
      * `:fill_extrusion` - An extruded (3D) polygon.
      * `:raster` - Raster map textures such as satellite imagery.
      * `:hillshade` - Client-side hillshading visualization based on DEM data.
      * `:background` - The background color or pattern of the map.

    * `:source` - Name of a source description to be used for the layer. Required for all layer
      types except `:background`.

  ## Options

    * `:filter` - A expression specifying conditions on source features. Only features that match
      the filter are displayed.

    * `:layout` - Layout properties for the layer.

    * `:maxzoom` - Optional number between 0 and 24 inclusive. The maximum zoom level for the
      layer. At zoom levels equal to or greater than the `:maxzoom`, the layer will be hidden

    * `:metadata` - Arbitrary properties useful to track with the layer, but do not influence
      rendering. Properties should be prefixed to avoid collisions

    * `:minzoom` - Optional number between 0 and 24 inclusive. The minimum zoom level for the
      layer. At zoom levels less than the `:minzoom`, the layer will be hidden.

    * `:paint` - Default paint properties for this layer.

  ## Type specific

    * `:source_layer` - Layer to use from a vector tile source. Required for vector tile sources;
      prohibited for all other source types, including GeoJSON sources.

  ## Examples
      |> Ml.add_layer(id: "rwanda-provinces",
          type: :fill,
          source: "rwanda-provinces",
          paint: [fill_color: "#4A9661"]
      )

  See [the docs](https://maplibre.org/maplibre-gl-js-docs/style-spec/layers/) for more details.
  """
  @spec add_layer(t(), keyword()) :: t()
  def add_layer(ml, opts) do
    validade_layer!(ml, opts)
    layer = opts_to_ml_props(opts)
    layers = List.insert_at(ml.spec["layers"], -1, layer)
    update_in(ml.spec, fn spec -> Map.put(spec, "layers", layers) end)
  end

  @doc """
  Same as `add_layer/2` but puts the given layer immediately below the labels
  """
  @spec add_layer_below_labels(t(), keyword()) :: t()
  def add_layer_below_labels(%_{spec: %{"layers" => layers}} = ml, opts) do
    validade_layer!(ml, opts)
    labels = Enum.find_index(layers, &(&1["type"] == "symbol"))
    layer = opts_to_ml_props(opts)
    updated_layers = List.insert_at(layers, labels, layer)
    update_in(ml.spec, fn spec -> Map.put(spec, "layers", updated_layers) end)
  end

  @doc """
  Updates a layer that was already defined in the specification
  """
  @spec update_layer(t(), String.t(), keyword()) :: t()
  def update_layer(%_{spec: %{"layers" => layers}} = ml, id, opts) do
    updated_fields = opts_to_ml_props(opts)
    index = Enum.find_index(layers, &(&1["id"] == id))
    validate_layer_update!(index, id, layers, ml, opts)
    updated_layer = layers |> Enum.at(index) |> Map.merge(updated_fields)
    updated_layers = List.replace_at(layers, index, updated_layer)
    update_in(ml.spec, fn spec -> Map.put(spec, "layers", updated_layers) end)
  end

  defp validade_layer!(ml, opts) do
    id = opts[:id]
    type = opts[:type]
    source = opts[:source]

    validate_layer_id!(ml, id)
    validate_layer_type!(type)
    if type != :background, do: validate_layer_source!(ml, source)
  end

  defp validate_layer_update!(index, id, layers, ml, opts) do
    if index == nil do
      layers = Enum.map_join(layers, ", ", &inspect(&1["id"]))

      raise ArgumentError,
            "layer #{inspect(id)} was not found. Current available layers are: #{layers}"
    end

    type = opts[:type]
    source = opts[:source]
    if type, do: validate_layer_type!(type)
    if source, do: validate_layer_source!(ml, source)
  end

  defp validate_layer_id!(_ml, nil) do
    raise ArgumentError,
          "layer id is required"
  end

  defp validate_layer_id!(ml, id) do
    if Enum.find(ml.spec["layers"], &(&1["id"] == id)) do
      raise ArgumentError,
            "The #{inspect(id)} layer already exists on the map. If you want to update a layer, use the #{inspect("update_layer/3")} function instead"
    end
  end

  defp validate_layer_type!(nil) do
    raise ArgumentError,
          "layer type is required"
  end

  defp validate_layer_type!(type) do
    layer_types = [
      :background,
      :fill,
      :line,
      :symbol,
      :raster,
      :circle,
      :fill_extrusion,
      :heatmap,
      :hillshade
    ]

    if type not in layer_types do
      types = layer_types |> Enum.map_join(", ", &inspect/1)

      raise ArgumentError,
            "unknown layer type, expected one of #{types}, got: #{inspect(type)}"
    end
  end

  defp validate_layer_source!(_ml, nil) do
    raise ArgumentError,
          "layer source is required"
  end

  defp validate_layer_source!(ml, source) do
    if not Map.has_key?(ml.spec["sources"], source) do
      sources = Map.keys(ml.spec["sources"]) |> Enum.map_join(", ", &inspect/1)

      raise ArgumentError,
            "source #{inspect(source)} was not found. The source must be present in the style before it can be associated with a layer. Current available sources are: #{sources}"
    end
  end

  @doc """
  Sets the light options in the specification.

  A style's light property provides a global light source for that style. Since this property is
  the light used to light extruded features, you will only see visible changes to your map style
  when modifying this property if you are using extrusions.

  ## Options

    * `:anchor` - Whether extruded geometries are lit relative to the map or viewport. "map": The
      position of the light source is aligned to the rotation of the map. "viewport": The position
      of the light source is aligned to the rotation of the viewport. Default: "viewport"

    * `:color` - Color tint for lighting extruded geometries. Default: "#ffffff"

    * `:intensity` - Intensity of lighting (on a scale from 0 to 1). Higher numbers will present
      as more extreme contrast. Default: 0.5

    * `:position` - Position of the light source relative to lit (extruded) geometries, in {r
      radial coordinate, a azimuthal angle, p polar angle} where r indicates the distance from the
      center of the base of an object to its light, a indicates the position of the light relative
      to 0° (0° when light.anchor is set to viewport corresponds to the top of the viewport, or 0°
      when light.anchor is set to map corresponds to due north, and degrees proceed clockwise),
      and p indicates the height of the light (from 0°, directly above, to 180°, directly below).
      Default: {1.15, 210, 30}

  See [the docs](https://maplibre.org/maplibre-gl-js-docs/style-spec/light/) for more details.
  """
  @spec light(t(), keyword()) :: t()
  def light(ml, opts) do
    light = opts_to_ml_props(opts)
    update_in(ml.spec, fn spec -> Map.put(spec, "light", light) end)
  end

  @doc """
  Sets the sprite url in the specification.

  A style's sprite property supplies a URL template for loading small images to use in rendering
  `:background_pattern`, `:fill_pattern`, `:line_pattern`,`:fill_extrusion_pattern` and `:icon_image` style
  properties.

  See [the docs](https://maplibre.org/maplibre-gl-js-docs/style-spec/sprite/) for more details.
  """
  @spec sprite(t(), String.t()) :: t()
  def sprite(ml, sprite) when is_binary(sprite) do
    update_in(ml.spec, fn spec -> Map.put(spec, "sprite", sprite) end)
  end

  @doc """
  Sets the glyphs url in the specification.

  A style's glyphs property provides a URL template for loading signed-distance-field glyph sets
  in PBF format.

  See [the docs](https://maplibre.org/maplibre-gl-js-docs/style-spec/glyphs/) for more details.
  """
  @spec glyphs(t(), String.t()) :: t()
  def glyphs(ml, glyphs) when is_binary(glyphs) do
    update_in(ml.spec, fn spec -> Map.put(spec, "glyphs", glyphs) end)
  end

  @doc """
  Defines a global default transition settings in the specification.

  A transition property controls timing for the interpolation between a transitionable style
  property's previous value and new value. A style's root transition property provides global
  transition defaults for that style.

  See [the docs](https://maplibre.org/maplibre-gl-js-docs/style-spec/transition/) for more
  details.
  """
  @spec transition(t(), keyword()) :: t()
  def transition(ml, opts) do
    transition = opts_to_ml_props(opts)
    update_in(ml.spec, fn spec -> Map.put(spec, "transition", transition) end)
  end

  @doc """
  Adds or updates the map metadata properties. Metadata are arbitrary properties useful to track
  with the style, but do not influence rendering. Properties should be prefixed to avoid
  collisions, like "mapbox:".
  """
  @spec metadata(t(), String.t(), String.t()) :: t()
  def metadata(ml, key, value) do
    metadata = %{key => value}
    current_metadata = if ml.spec["metadata"], do: ml.spec["metadata"], else: %{}
    updated_metadata = Map.merge(current_metadata, metadata)
    update_in(ml.spec, fn spec -> Map.put(spec, "metadata", updated_metadata) end)
  end

  # Helpers

  defp opts_to_ml_props(opts) do
    opts |> Map.new() |> to_ml()
  end

  defp to_ml(value) when value in [true, false, nil], do: value

  defp to_ml(atom) when is_atom(atom), do: to_ml_key(atom)

  defp to_ml(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {to_ml(key), to_ml(value)}
    end)
  end

  defp to_ml([{key, _} | _] = keyword) when is_atom(key) do
    Map.new(keyword, fn {key, value} ->
      {to_ml(key), to_ml(value)}
    end)
  end

  defp to_ml(list) when is_list(list) do
    Enum.map(list, &to_ml/1)
  end

  defp to_ml(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.map(&to_ml/1)
  end

  defp to_ml(value), do: value

  defp to_ml_key(key) when is_atom(key) and key in @to_kebab do
    key |> to_string() |> snake_to_kebab()
  end

  defp to_ml_key(key) when is_atom(key) do
    key |> to_string() |> snake_to_camel()
  end

  defp snake_to_kebab(string) do
    String.replace(string, "_", "-")
  end

  defp snake_to_camel(string) do
    [part | parts] = String.split(string, "_")
    Enum.join([String.downcase(part, :ascii) | Enum.map(parts, &String.capitalize(&1, :ascii))])
  end

  defp to_style("http" <> _rest = style), do: Req.get!(style).body
  defp to_style(%{}), do: %{"version" => 8}
  defp to_style(style) when is_map(style), do: style
  defp to_style(style), do: Jason.decode!(style)
end
