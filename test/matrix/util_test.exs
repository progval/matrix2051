defmodule M51.Matrix.UtilsTest do
  use ExUnit.Case
  doctest M51.Matrix.Utils

  test "urlmerge" do
    assert M51.Matrix.Utils.urlmerge("http://example.com", "/foo/bar/%20test") == "http://example.com/foo/bar/%20test"
    assert M51.Matrix.Utils.urlmerge("http://example.com/", "/foo/bar/%20test") == "http://example.com/foo/bar/%20test"
  end
end
