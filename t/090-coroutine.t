# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 2);

$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';

run_tests();

__DATA__

=== TEST 1: basic coroutine print
--- config
    location /lua {
        content_by_lua '
            local cc, cr, cy = coroutine.create, coroutine.resume, coroutine.yield

            function f()
                local cnt = 0
                while true do
                    ngx.say("Hello, ", cnt)
                    cy()
                    cnt = cnt + 1
                end
            end

            local c = cc(f)
            for i=1,3 do
                cr(c)
                ngx.say("***")
            end
        ';
    }
--- request
GET /lua
--- response_body
Hello, 0
***
Hello, 1
***
Hello, 2
***
--- no_error_log
[error]



=== TEST 2: basic coroutine2
--- config
    location /lua {
        content_by_lua '
            function f(fid)
                local cnt = 0
                while true do
                    ngx.say("cc", fid, ": ", cnt)
                    coroutine.yield()
                    cnt = cnt + 1
                end
            end

            local ccs = {}
            for i=1,3 do
                ccs[#ccs+1] = coroutine.create(function() f(i) end)
            end

            for i=1,9 do
                local cc = table.remove(ccs, 1)
                coroutine.resume(cc)
                ccs[#ccs+1] = cc
            end
        ';
    }
--- request
GET /lua
--- response_body
cc1: 0
cc2: 0
cc3: 0
cc1: 1
cc2: 1
cc3: 1
cc1: 2
cc2: 2
cc3: 2
--- no_error_log
[error]



=== TEST 3: basic coroutine and cosocket
--- config
    resolver $TEST_NGINX_RESOLVER;
    location /lua {
        content_by_lua '
            function worker(url)
                local sock = ngx.socket.tcp()
                local ok, err = sock:connect(url, 80)
                coroutine.yield()
                if not ok then
                    ngx.say("failed to connect to: ", url, " error: ", err)
                    return
                end
                coroutine.yield()
                ngx.say("successfully connected to: ", url)
                sock:close()
            end

            local urls = {
                "www.taobao.com",
                "www.baidu.com",
                "www.qq.com"
            }

            local ccs = {}
            for i, url in ipairs(urls) do
                local cc = coroutine.create(function() worker(url) end)
                ccs[#ccs+1] = cc
            end

            while true do
                if #ccs == 0 then break end
                local cc = table.remove(ccs, 1)
                local ok = coroutine.resume(cc)
                if ok then
                    ccs[#ccs+1] = cc
                end
            end

            ngx.say("*** All Done ***")
        ';
    }
--- request
GET /lua
--- response_body
successfully connected to: www.taobao.com
successfully connected to: www.baidu.com
successfully connected to: www.qq.com
*** All Done ***
--- error_log
lua coroutine: runtime error: cannot resume dead coroutine



=== TEST 4: coroutine.wrap(generate prime numbers)
--- config
    location /lua {
        content_by_lua '
            -- generate all the numbers from 2 to n
            function gen (n)
              return coroutine.wrap(function ()
                for i=2,n do coroutine.yield(i) end
              end)
            end

            -- filter the numbers generated by g, removing multiples of p
            function filter (p, g)
              return coroutine.wrap(function ()
                while 1 do
                  local n = g()
                  if n == nil then return end
                  if math.mod(n, p) ~= 0 then coroutine.yield(n) end
                end
              end)
            end

            N = 10 
            x = gen(N)		-- generate primes up to N
            while 1 do
              local n = x()		-- pick a number until done
              if n == nil then break end
              ngx.say(n)		-- must be a prime number
              x = filter(n, x)	-- now remove its multiples
            end
        ';
    }
--- request
GET /lua
--- response_body
2
3
5
7
--- no_error_log
[error]



=== TEST 5: coroutine.wrap(generate prime numbers,reset create and resume)
--- config
    location /lua {
        content_by_lua '
            coroutine.create = nil
            coroutine.resume = nil
            -- generate all the numbers from 2 to n
            function gen (n)
              return coroutine.wrap(function ()
                for i=2,n do coroutine.yield(i) end
              end)
            end

            -- filter the numbers generated by g, removing multiples of p
            function filter (p, g)
              return coroutine.wrap(function ()
                while 1 do
                  local n = g()
                  if n == nil then return end
                  if math.mod(n, p) ~= 0 then coroutine.yield(n) end
                end
              end)
            end

            N = 10 
            x = gen(N)		-- generate primes up to N
            while 1 do
              local n = x()		-- pick a number until done
              if n == nil then break end
              ngx.say(n)		-- must be a prime number
              x = filter(n, x)	-- now remove its multiples
            end
        ';
    }
--- request
GET /lua
--- response_body
2
3
5
7
--- no_error_log
[error]



=== TEST 6: coroutine.wrap(generate fib)
--- config
    location /lua {
        content_by_lua '
            function generatefib (n)
              return coroutine.wrap(function ()
                local a,b = 1, 1
                while a <= n do
                  coroutine.yield(a)
                  a, b = b, a+b
                end
              end)
            end

            -- In lua, because OP_TFORLOOP uses luaD_call to execute the iterator function,
            -- and luaD_call is a C function, so we can not yield in the iterator function.
            -- So the following case(using for loop) will be failed.
            -- Luajit is OK.
            if package.loaded["jit"] then
                for i in generatefib(1000) do ngx.say(i) end
            else
                local gen = generatefib(1000)
                while true do
                    local i = gen()
                    if not i then break end
                    ngx.say(i)
                end
            end
        ';
    }
--- request
GET /lua
--- response_body
1
1
2
3
5
8
13
21
34
55
89
144
233
377
610
987
--- no_error_log
[error]



=== TEST 7: coroutine wrap and cosocket
--- config
    resolver $TEST_NGINX_RESOLVER;
    location /lua {
        content_by_lua '
            function worker(url)
                local sock = ngx.socket.tcp()
                local ok, err = sock:connect(url, 80)
                coroutine.yield()
                if not ok then
                    ngx.say("failed to connect to: ", url, " error: ", err)
                    return
                end
                coroutine.yield()
                ngx.say("successfully connected to: ", url)
                sock:close()
            end

            local urls = {
                "www.taobao.com",
                "www.baidu.com",
                "www.qq.com"
            }

            local cfs = {}
            for i, url in ipairs(urls) do
                local cf = coroutine.wrap(function() worker(url) end)
                cfs[#cfs+1] = cf
            end

            for i=1,3 do cfs[i]() end
            for i=1,3 do cfs[i]() end
            for i=1,3 do cfs[i]() end

            ngx.say("*** All Done ***")
        ';
    }
--- request
GET /lua
--- response_body
successfully connected to: www.taobao.com
successfully connected to: www.baidu.com
successfully connected to: www.qq.com
*** All Done ***
--- no_error_log
[error]



=== TEST 8: coroutine status, running
--- config
    location /lua {
        content_by_lua '
            local cc, cr, cy = coroutine.create, coroutine.resume, coroutine.yield
            local st, rn = coroutine.status, coroutine.running

            function f(self)
                local cnt = 0
                if rn() ~= self then ngx.say("error"); return end
                ngx.say(st(self)) --running
                cy()
                -- Status normal is not support now. Actually user coroutines have no 
                -- sub-coroutine, the main thread holds all of the coroutines.
                local c = cc(function(father) ngx.say(st(father)) end) -- normal
                cr(c, self)
            end

            local c = cc(f)
            ngx.say(st(c)) --suspended
            cr(c, c)
            ngx.say(st(c)) --suspended
            cr(c, c)
            ngx.say(st(c)) --dead
        ';
    }
--- request
GET /lua
--- response_body
suspended
running
suspended
suspended
dead
--- no_error_log
[error]



=== TEST 9: entry coroutine call yield
--- config
    location /lua {
        content_by_lua '
            coroutine.yield()
            ngx.say("hello")
        ';
    }
--- request
GET /lua
--- error_code: 500
--- error_log
entry coroutine can not yield



=== TEST 10: thread traceback (multi-thread)
--- config
    location /lua {
        content_by_lua '
            local f = function(cr) coroutine.resume(cr) end
            -- emit a error
            local g = function() unknown.unknown = 1 end
            local l1 = coroutine.create(f)
            local l2 = coroutine.create(g)
            coroutine.resume(l1, l2)
            ngx.say("hello")
        ';
    }
--- request
GET /lua
--- response_body
hello
--- error_log eval
["stack traceback:", "coroutine 0:", "coroutine 1:", "coroutine 2:"]



=== TEST 11: thread traceback (only the entry thread)
--- config
    location /lua {
        content_by_lua '
            -- emit a error
            unknown.unknown = 1
            ngx.say("hello")
        ';
    }
--- request
GET /lua
--- error_code: 500
--- error_log eval
["stack traceback:", "coroutine 0:"]



=== TEST 12: bug: resume dead coroutine with args
--- config
    location /lua {
        content_by_lua '
            function print(...)
                local args = {...}
                local is_first = true
                for i,v in ipairs(args) do
                    if is_first then
                        is_first = false
                    else
                        ngx.print(" ")
                    end
                    ngx.print(v)
                end
                ngx.print("\\\n")
            end

            function foo (a)
                print("foo", a)
                return coroutine.yield(2*a)
            end

            co = coroutine.create(function (a,b)
                    print("co-body", a, b)
                    local r = foo(a+1)
                    print("co-body", r)
                    local r, s = coroutine.yield(a+b, a-b)
                    print("co-body", r, s)
                    return b, "end"
                end)

            print("main", coroutine.resume(co, 1, 10))
            print("main", coroutine.resume(co, "r"))
            print("main", coroutine.resume(co, "x", "y"))
            print("main", coroutine.resume(co, "x", "y"))
        ';
    }
--- request
GET /lua
--- response_body
co-body 1 10
foo 2
main true 4
co-body r
main true 11 -9
co-body x y
main true 10 end
main false cannot resume dead coroutine
--- error_log
lua coroutine: runtime error: cannot resume dead coroutine

