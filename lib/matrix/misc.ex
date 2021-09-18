defmodule Matrix2051.Matrix.Misc do
  def parse_userid(userid) do
    case String.split(userid, ":") do
      [local_name, hostname] ->
        if Regex.match?(~r|^[0-9a-z.=_/-]+$|, local_name) do
          if Regex.match?(~r/.*\s.*/u, hostname) do
            {:error, "\"" <> hostname <> "\" is not a valid hostname"}
            nil
          else
            {:ok, {local_name, hostname}}
          end
        else
          {:error,
           "your local name may only contain lowercase latin letters, digits, and the following characters: -.=_/"}
        end

      [nick] ->
        {:error,
         "must contain a colon (':'), to separate the username and hostname. For example: " <>
           nick <> ":matrix.org"}

      _ ->
        {:error, "must not contain more than one colon."}
    end
  end
end
