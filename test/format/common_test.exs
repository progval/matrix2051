##
# Copyright (C) 2021  Valentin Lorentz
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License version 3,
# as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
###

defmodule M51.FormatTest do
  use ExUnit.Case
  doctest M51.Format

  import Mox
  setup :set_mox_from_context
  setup :verify_on_exit!

  test "simple Matrix to IRC" do
    assert M51.Format.matrix2irc("foo") == "foo"
    assert M51.Format.matrix2irc("<b>foo</b>") == "\x02foo\x02"
    assert M51.Format.matrix2irc("<i>foo</i>") == "\x1dfoo\x1d"
    assert M51.Format.matrix2irc("<code>foo</code>") == "\x11foo\x11"
    assert M51.Format.matrix2irc("<pre>foo</pre>") == "\x11foo\x11"
    assert M51.Format.matrix2irc("<b>foo <i>bar</i> baz</b>") == "\x02foo \x1dbar\x1d baz\x02"

    assert M51.Format.matrix2irc("foo<br/>bar") == "foo\nbar"
    assert M51.Format.matrix2irc("foo<br/><br/>bar") == "foo\n\nbar"

    assert M51.Format.matrix2irc("<pre>foo<br/>bar</pre>") == "\x11foo\nbar\x11"
    assert M51.Format.matrix2irc("<pre>foo<br/><br/>bar</pre>") == "\x11foo\n\nbar\x11"
  end

  test "simple IRC to Matrix" do
    assert M51.Format.irc2matrix("foo") == {"foo", "foo"}
    assert M51.Format.irc2matrix("\x02foo\x02") == {"*foo*", "<b>foo</b>"}
    assert M51.Format.irc2matrix("\x02foo\x0f") == {"*foo*", "<b>foo</b>"}
    assert M51.Format.irc2matrix("\x02foo") == {"*foo*", "<b>foo</b>"}
    assert M51.Format.irc2matrix("\x1dfoo\x1d") == {"/foo/", "<i>foo</i>"}
    assert M51.Format.irc2matrix("\x1dfoo") == {"/foo/", "<i>foo</i>"}
    assert M51.Format.irc2matrix("\x11foo\x11") == {"`foo`", "<code>foo</code>"}

    assert M51.Format.irc2matrix("\x02foo \x1dbar\x1d baz\x02") ==
             {"*foo /bar/ baz*", "<b>foo </b><i><b>bar</b></i><b> baz</b>"}
  end

  test "interleaved IRC to Matrix" do
    assert M51.Format.irc2matrix("\x02foo \x1dbar\x0f baz") ==
             {"*foo /bar*/ baz", "<b>foo </b><i><b>bar</b></i> baz"}

    assert M51.Format.irc2matrix("\x02foo \x1dbar\x02 baz\x1d qux") ==
             {"*foo /bar* baz/ qux", "<b>foo </b><i><b>bar</b></i><i> baz</i> qux"}

    assert M51.Format.irc2matrix("\x1dfoo \x02bar\x0f baz") ==
             {"/foo *bar*/ baz", "<i>foo </i><i><b>bar</b></i> baz"}
  end

  test "Matrix colors to IRC" do
    assert M51.Format.matrix2irc(~s(<font data-mx-color="#FF0000">foo</font>)) ==
             "\x04FF0000foo\x0399,99"

    assert M51.Format.matrix2irc(~s(<font data-mx-color="FF0000">foo</font>)) ==
             "\x04FF0000foo\x0399,99"

    assert M51.Format.matrix2irc(
             ~s(<font data-mx-color="#FF0000" data-mx-bg-color="00FF00">foo</font>)
           ) == "\x04FF0000,00FF00foo\x0399,99"

    assert M51.Format.matrix2irc(~s(<font data-mx-bg-color="00FF00">foo</font>)) ==
             "\x04000000,00FF00\x0399foo\x0399,99"

    assert M51.Format.matrix2irc(
             ~s(<font data-mx-color="#FF0000" data-mx-bg-color="#00FF00">foo) <>
               ~s(<font data-mx-color="#00FF00" data-mx-bg-color="#0000FF">bar) <>
               ~s(</font></font>)
           ) == "\x04FF0000,00FF00foo\x0400FF00,0000FFbar\x04FF0000,00FF00\x0399,99"
  end

  test "IRC basic colors to Matrix" do
    assert M51.Format.irc2matrix("\x034foo") ==
             {"foo", ~s(<font data-mx-color="#FF0000">foo</font>)}

    assert M51.Format.irc2matrix("\x0304foo") ==
             {"foo", ~s(<font data-mx-color="#FF0000">foo</font>)}

    assert M51.Format.irc2matrix("\x0304foo \x0303bar") ==
             {"foo bar",
              ~s(<font data-mx-color="#FF0000">foo </font>) <>
                ~s(<font data-mx-color="#009300">bar</font>)}

    assert M51.Format.irc2matrix("\x0304,03foo") ==
             {"foo", ~s(<font data-mx-color="#FF0000" data-mx-bg-color="#009300">foo</font>)}
  end

  test "IRC hex colors to Matrix" do
    assert M51.Format.irc2matrix("\x04FF0000,foo\x0399,99") ==
             {"foo", ~s(<font data-mx-color="#FF0000">foo</font>)}

    assert M51.Format.irc2matrix("\x04FF0000,00FF00foo\x0399,99") ==
             {"foo", ~s(<font data-mx-color="#FF0000" data-mx-bg-color="#00FF00">foo</font>)}

    assert M51.Format.irc2matrix("\x04FF0000,00FF00foo\x0400FF00,0000FFbar\x04FF0000,00FF00") ==
             {"foobar",
              ~s(<font data-mx-color="#FF0000" data-mx-bg-color="#00FF00">foo</font>) <>
                ~s(<font data-mx-color="#00FF00" data-mx-bg-color="#0000FF">bar</font>)}

    assert M51.Format.irc2matrix(
             "\x04FF0000,00FF00foo\x0400FF00,0000FFbar\x04FF0000,00FF00\x0399,99"
           ) ==
             {"foobar",
              ~s(<font data-mx-color="#FF0000" data-mx-bg-color="#00FF00">foo</font>) <>
                ~s(<font data-mx-color="#00FF00" data-mx-bg-color="#0000FF">bar</font>)}
  end

  test "Matrix link to IRC" do
    MockHTTPoison
    |> expect(:get, 4, fn url ->
      assert url == "https://example.org/.well-known/matrix/client"

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: ~s({"m.homeserver": {"base_url": "https://api.example.org"}})
       }}
    end)
    |> expect(:get, 1, fn url ->
      assert url == "https://homeserver.org/.well-known/matrix/client"

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: ~s({"m.homeserver": {"base_url": "https://api.homeserver.org"}})
       }}
    end)

    assert M51.Format.matrix2irc(~s(<a href="https://example.org">foo</a>)) ==
             "foo <https://example.org>"

    assert M51.Format.matrix2irc(~s(<a href="https://example.org">https://example.org</a>)) ==
             "https://example.org"

    assert M51.Format.matrix2irc(~s(<img src="https://example.org" />)) == "https://example.org"

    assert M51.Format.matrix2irc(~s(<img src="mxc://example.org/foo" />)) ==
             "https://api.example.org/_matrix/media/r0/download/example.org/foo"

    assert M51.Format.matrix2irc(~s(<img alt="image.png" src="mxc://example.org/foo" />)) ==
             "https://api.example.org/_matrix/media/r0/download/example.org/foo"

    assert M51.Format.matrix2irc(~s(<img src="mxc://example.org/foo" title="an image"/>)) ==
             "an image <https://api.example.org/_matrix/media/r0/download/example.org/foo>"

    assert M51.Format.matrix2irc(
             ~s(<img src="mxc://example.org/foo" alt="an image" title="blah"/>)
           ) ==
             "an image <https://api.example.org/_matrix/media/r0/download/example.org/foo>"

    assert M51.Format.matrix2irc(
             ~s(<img src="mxc://example.org/foo" alt="an image" title="blah"/>),
             "homeserver.org"
           ) ==
             "an image <https://api.homeserver.org/_matrix/media/r0/download/example.org/foo>"

    assert M51.Format.matrix2irc(~s(<img" />)) ==
             ""

    assert M51.Format.matrix2irc(~s(<img  title="an image"/>)) ==
             "an image"

    assert M51.Format.matrix2irc(~s(<img alt="an image" title="blah"/>)) ==
             "an image"

    assert M51.Format.matrix2irc(~s(<a>foo</a>)) == "foo"

    assert M51.Format.matrix2irc(~s(<img/>)) == ""
  end

  test "Matrix link to IRC (404 on well-known)" do
    MockHTTPoison
    |> expect(:get, 1, fn url ->
      assert url == "https://example.org/.well-known/matrix/client"

      {:ok,
       %HTTPoison.Response{
         status_code: 404,
         body: ~s(this is not JSON)
       }}
    end)

    assert M51.Format.matrix2irc(~s(<img src="mxc://example.org/foo" />)) ==
             "https://example.org/_matrix/media/r0/download/example.org/foo"
  end

  test "Matrix link to IRC (connection error on well-known)" do
    MockHTTPoison
    |> expect(:get, 1, fn url ->
      assert url == "https://example.org/.well-known/matrix/client"
      {:error, %HTTPoison.Error{reason: :connrefused}}
    end)

    # can log "failed with connection error [connrefused]" warning
    Logger.remove_backend(:console)

    assert M51.Format.matrix2irc(~s(<img src="mxc://example.org/foo" />)) ==
             "https://example.org/_matrix/media/r0/download/example.org/foo"

    Logger.add_backend(:console)
  end

  test "IRC link to Matrix" do
    assert M51.Format.irc2matrix("foo https://example.org") ==
             {"foo https://example.org",
              ~s(foo <a href="https://example.org">https://example.org</a>)}
  end

  test "Matrix list to IRC" do
    assert M51.Format.matrix2irc("foo<ul><li>bar</li><li>baz</li></ul>qux") ==
             "foo\n* bar\n* baz\nqux"

    assert M51.Format.matrix2irc("foo<ol><li>bar</li><li>baz</li></ol>qux") ==
             "foo\n* bar\n* baz\nqux"
  end

  test "Matrix newline to IRC" do
    assert M51.Format.matrix2irc("foo<br>bar") == "foo\nbar"
    assert M51.Format.matrix2irc("foo<br/>bar") == "foo\nbar"
    assert M51.Format.matrix2irc("foo<br/><br/>bar") == "foo\n\nbar"
    assert M51.Format.matrix2irc("<p>foo</p>bar") == "foo\nbar"
    assert M51.Format.matrix2irc("foo\nbar") == "foo bar"
    assert M51.Format.matrix2irc("foo\n \nbar") == "foo bar"
    assert M51.Format.matrix2irc("<p>foo</p>\n<p>bar</p>") == "foo\nbar"
    assert M51.Format.matrix2irc("<p>foo</p>\n<p>bar</p>\n<p>baz</p>") == "foo\nbar\nbaz"
  end

  test "IRC newline to Matrix" do
    assert M51.Format.irc2matrix("foo\nbar") == {"foo\nbar", "foo<br/>bar"}
  end

  test "mx-reply to IRC" do
    assert M51.Format.matrix2irc(
             "<mx-reply><blockquote><a href=\"https://matrix.to/#/!blahblah:matrix.org/$event1\">In reply to</a> <a href=\"https://matrix.to/#/@nick:example.org\">@nick:example.org</a><br>first message</blockquote></mx-reply>second message"
           ) == "second message"
  end

  test "Matrix mentions to IRC" do
    # Format emitted by Element and many other apps:
    assert M51.Format.matrix2irc(
             "<a href=\"https://matrix.to/#/@user:example.org\">user</a>: mention"
           ) == "user:example.org: mention"

    assert M51.Format.matrix2irc(
             "mentioning <a href=\"https://matrix.to/#/@user:example.org\">user</a>"
           ) == "mentioning user:example.org"

    # Fails because mochiweb_html drops the space, see:
    # https://github.com/mochi/mochiweb/issues/166
    # assert M51.Format.matrix2irc(
    #          "mentioning <a href=\"https://matrix.to/#/@user1:example.org\">user1</a> <a href=\"https://matrix.to/#/@user2:example.org\">user2</a>"
    #        ) == "mentioning user1:example.org user2:example.org"

    # Correct format according to the spec:
    assert M51.Format.matrix2irc(
             "mentioning <a href=\"https://matrix.to/#/%40correctlyencoded%3Aexample.org\">correctly encoded user</a>"
           ) == "mentioning correctlyencoded:example.org"
  end

  test "IRC mentions to Matrix" do
    assert M51.Format.irc2matrix("user:example.org: mention", ["foo"]) ==
             {"user:example.org: mention", "user:example.org: mention"}

    assert M51.Format.irc2matrix("user:example.org: mention", ["foo", "user:example.org"]) ==
             {"user:example.org: mention",
              "<a href=\"https://matrix.to/#/@user:example.org\">user</a>: mention"}

    assert M51.Format.irc2matrix("mentioning user:example.org", ["foo"]) ==
             {"mentioning user:example.org", "mentioning user:example.org"}

    assert M51.Format.irc2matrix("user:example.org: mention", ["foo", "user:example.org"]) ==
             {"user:example.org: mention",
              "<a href=\"https://matrix.to/#/@user:example.org\">user</a>: mention"}

    assert M51.Format.irc2matrix("mentioning user:example.org", ["foo", "user:example.org"]) ==
             {"mentioning user:example.org",
              "mentioning <a href=\"https://matrix.to/#/@user:example.org\">user</a>"}

    assert M51.Format.irc2matrix("mentioning EarlyAdopter:example.org", [
             "foo",
             "EarlyAdopter:example.org"
           ]) ==
             {"mentioning EarlyAdopter:example.org",
              "mentioning <a href=\"https://matrix.to/#/@EarlyAdopter:example.org\">EarlyAdopter</a>"}
  end

  test "Matrix room mentions to IRC" do
    assert M51.Format.matrix2irc(
             "join <a href=\"https://matrix.to/#/#room:example.org\">#room</a>"
           ) == "join #room:example.org"

    assert M51.Format.matrix2irc(
             "join <a href=\"https://matrix.to/#/%23room%3Aexample.org\">#room</a>"
           ) == "join #room:example.org"

    assert M51.Format.matrix2irc(
             "join <a href=\"https://matrix.to/#/!room:example.org\">#room</a>"
           ) == "join !room:example.org"

    assert M51.Format.matrix2irc(
             "join <a href=\"https://matrix.to/#/%21room%3Aexample.org\">#room</a>"
           ) == "join !room:example.org"

    assert M51.Format.matrix2irc(
             "join <a href=\"https://matrix.to/#/#room:example.org/%24event%3Aexample.org\">#room</a>"
           ) == "join #room:example.org"

    assert M51.Format.matrix2irc(
             "join <a href=\"https://matrix.to/#/%23room%3Aexample.org/%24event%3Aexample.org\">#room</a>"
           ) == "join #room:example.org"

    assert M51.Format.matrix2irc(
             "join <a href=\"https://matrix.to/#/#room:example.org?via=elsewhere\">#room</a>"
           ) == "join #room:example.org"

    assert M51.Format.matrix2irc(
             "join <a href=\"https://matrix.to/#/%23room%3Aexample.org?via=elsewhere\">#room</a>"
           ) == "join #room:example.org"
  end

  test "Corrupt matrix.to link" do
    assert M51.Format.matrix2irc("join <a href=\"https://matrix.to/#/%23\">oh no</a>") ==
             "join oh no <https://matrix.to/#/%23\>"
  end
end
