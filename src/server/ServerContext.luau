--!nonstrict
-- Holds the live service context after boot so trusted server-side tooling (the engine test hook) can reach it.
-- Nothing client-facing reads this. Set by init.server.luau once every service has started.
return { ctx = nil }
