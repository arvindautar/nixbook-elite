# notify-users TITLE BODY: a desktop notification in every open session.
# System services can't reach those sessions on their own.
{ pkgs }:

pkgs.writeShellScript "notify-users" ''
  title="$1"
  body="$2"
  for uid in $(${pkgs.systemd}/bin/loginctl list-users --no-legend | ${pkgs.gawk}/bin/awk '{print $1}'); do
    user=$(${pkgs.coreutils}/bin/id -nu "$uid") || continue
    [ -S "/run/user/$uid/bus" ] || continue
    ${pkgs.util-linux}/bin/runuser -u "$user" -- env \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
      ${pkgs.libnotify}/bin/notify-send -a "Systeemupdate" "$title" "$body" || true
  done
''
