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

defmodule Matrix2051.FormatTest do
  use ExUnit.Case
  doctest Matrix2051.Format

  test "simple Matrix to IRC" do
    assert Matrix2051.Format.matrix2irc("foo") == "foo"
    assert Matrix2051.Format.matrix2irc("<b>foo</b>") == "\x02foo\x02"
    assert Matrix2051.Format.matrix2irc("<i>foo</i>") == "\x1dfoo\x1d"
    assert Matrix2051.Format.matrix2irc("<pre>foo</pre>") == "\x11foo\x11"
    assert Matrix2051.Format.matrix2irc("<code>foo</code>") == "\x11foo\x11"

    assert Matrix2051.Format.matrix2irc("<b>foo <i>bar</i> baz</b>") ==
             "\x02foo \x1dbar\x1d baz\x02"
  end

  test "simple IRC to Matrix" do
    assert Matrix2051.Format.irc2matrix("foo") == {"foo", "foo"}
    assert Matrix2051.Format.irc2matrix("\x02foo\x02") == {"*foo*", "<b>foo</b>"}
    assert Matrix2051.Format.irc2matrix("\x02foo\x0f") == {"*foo*", "<b>foo</b>"}
    assert Matrix2051.Format.irc2matrix("\x02foo") == {"*foo*", "<b>foo</b>"}
    assert Matrix2051.Format.irc2matrix("\x1dfoo\x1d") == {"/foo/", "<i>foo</i>"}
    assert Matrix2051.Format.irc2matrix("\x1dfoo") == {"/foo/", "<i>foo</i>"}
    assert Matrix2051.Format.irc2matrix("\x11foo\x11") == {"`foo`", "<code>foo</code>"}

    assert Matrix2051.Format.irc2matrix("\x02foo \x1dbar\x1d baz\x02") ==
             {"*foo /bar/ baz*", "<b>foo <i>bar</i> baz</b>"}
  end

  test "interleaved IRC to Matrix" do
    # TODO:
    # assert Matrix2051.Format.irc2matrix("\x02foo \x1dbar\x0f baz") ==
    #          {"*foo /bar/* baz", "<b>foo <i>bar</i></b> baz"}

    # TODO:
    # assert Matrix2051.Format.irc2matrix("\x02foo \x1dbar\x02 baz qux\x1d") ==
    #          {"*foo /bar* baz/", "<b>foo <i>bar</i></b><i> baz</i>"}

    assert Matrix2051.Format.irc2matrix("\x1dfoo \x02bar\x0f baz") ==
             {"/foo *bar*/ baz", "<i>foo <b>bar</b></i> baz"}
  end

  test "Matrix colors to IRC" do
    assert Matrix2051.Format.matrix2irc(
             ~s(<font data-mx-color="FF0000" data-mx-bg-color="00FF00">foo</font>)
           ) == "\x04FF0000,00FF00foo\x0399,99"

    assert Matrix2051.Format.matrix2irc(
             ~s(<font data-mx-color="FF0000" data-mx-bg-color="00FF00">foo) <>
               ~s(<font data-mx-color="00FF00" data-mx-bg-color="0000FF">bar) <>
               ~s(</font></font>)
           ) == "\x04FF0000,00FF00foo\x0400FF00,0000FFbar\x04FF0000,00FF00\x0399,99"
  end

  test "Matrix link to IRC" do
    assert Matrix2051.Format.matrix2irc(~s(<a href="https://example.org">foo</a>)) ==
             "foo <https://example.org>"

    assert Matrix2051.Format.matrix2irc(~s(<img src="https://example.org" />)) ==
             "https://example.org"

    assert Matrix2051.Format.matrix2irc(~s(<a>foo</a>)) == "foo"

    assert Matrix2051.Format.matrix2irc(~s(<img/>)) == ""
  end

  test "IRC link to Matrix" do
    assert Matrix2051.Format.irc2matrix("foo https://example.org") ==
             {"foo https://example.org",
              ~s(foo <a href="https://example.org">https://example.org</a>)}
  end

  test "Matrix list to IRC" do
    assert Matrix2051.Format.matrix2irc("foo<ul><li>bar</li><li>baz</li></ul>qux") ==
             "foo\n* bar\n* baz\nqux"

    assert Matrix2051.Format.matrix2irc("foo<ol><li>bar</li><li>baz</li></ol>qux") ==
             "foo\n* bar\n* baz\nqux"
  end

  test "Matrix newline to IRC" do
    assert Matrix2051.Format.matrix2irc("foo<br>bar") == "foo\nbar"
    assert Matrix2051.Format.matrix2irc("foo<br/>bar") == "foo\nbar"
    assert Matrix2051.Format.matrix2irc("<p>foo</p>bar") == "foo\nbar"
  end

  test "IRC newline to Matrix" do
    assert Matrix2051.Format.irc2matrix("foo\nbar") == {"foo\nbar", "foo<br/>bar"}
  end

  test "mx-reply to IRC" do
    assert Matrix2051.Format.matrix2irc(
             "<mx-reply><blockquote><a href=\"https://matrix.to/#/!blahblah:matrix.org/$event1\">In reply to</a> <a href=\"https://matrix.to/#/@nick:example.org\">@nick:example.org</a><br>first message</blockquote></mx-reply>second message"
           ) == "second message"
  end

  test "Matrix mentions to IRC" do
    assert Matrix2051.Format.matrix2irc(
             "<a href=\"https://matrix.to/#/@user:example.org\">user</a>: mention"
           ) == "user:example.org: mention"

    assert Matrix2051.Format.matrix2irc(
             "mentioning <a href=\"https://matrix.to/#/@user:example.org\">user</a>"
           ) == "mentioning user:example.org"
  end

  test "IRC mentions to Matrix" do
    assert Matrix2051.Format.irc2matrix("user:example.org: mention", ["foo"]) ==
             {"user:example.org: mention", "user:example.org: mention"}

    assert Matrix2051.Format.irc2matrix("user:example.org: mention", ["foo", "user:example.org"]) ==
             {"user:example.org: mention",
              "<a href=\"https://matrix.to/#/@user:example.org\">user</a>: mention"}

    assert Matrix2051.Format.irc2matrix("mentioning user:example.org", ["foo"]) ==
             {"mentioning user:example.org", "mentioning user:example.org"}

    assert Matrix2051.Format.irc2matrix("mentioning user:example.org", ["foo", "user:example.org"]) ==
             {"mentioning user:example.org",
              "mentioning <a href=\"https://matrix.to/#/@user:example.org\">user</a>"}
  end
end
