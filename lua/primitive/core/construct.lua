
-------------------------------
-- CONSTRUCT LIBRARY
--
-- BY SHADOWSCION
-------------------------------
-- Feel free to use this file in your projects, but please change the below global table to your addon
local addon = Primitive


-------------------------------
local bit, math, util, table, isvector, WorldToLocal, LocalToWorld, Vector, Angle =
      bit, math, util, table, isvector, WorldToLocal, LocalToWorld, Vector, Angle

local math_sin, math_cos, math_tan, math_asin, math_acos, math_atan, math_atan2, math_rad, math_deg =
      math.sin, math.cos, math.tan, math.asin, math.acos, math.atan, math.atan2, math.rad, math.deg

local math_ceil, math_floor, math_round, math_min, math_max, math_clamp =
      math.ceil, math.floor, math.Round, math.min, math.max, math.Clamp

local table_insert, coroutine_yield =
      table.insert, coroutine.yield

local vec, ang = Vector(), Angle()
local vec_cross, vec_dot, vec_add, vec_sub, vec_mul, vec_div, vec_rotate, vec_lengthsqr, vec_normalize, vec_getnormalized, vec_angle =
      vec.Cross, vec.Dot, vec.Add, vec.Sub, vec.Mul, vec.Div, vec.Rotate, vec.LengthSqr, vec.Normalize, vec.GetNormalized, vec.Angle

local math_pi = math.pi
local math_tau = math.pi * 2


-------------------------------
addon.construct = { simpleton = {}, prefab = {}, util = {} }

local registerType, getType
local construct_types = {}

do

    --[[
        @FUNCTION: addon.construct.registerType

        @DESCRIPTION: Register a new construct type

        @PARAMETERS:
            [string] name -- the name of the new type
            [function]( param, data, threaded, physics )

        @RETURN:
    --]]
    function registerType( name, factory, data )
        if not istable( data ) then
            data = {}
        end

        data.name = name or "NO_NAME"
        construct_types[name] = { factory = factory, data = data }
    end
    addon.construct.registerType = registerType


    --[[
        @FUNCTION: addon.construct.getType

        @DESCRIPTION:

        @PARAMETERS:

        @RETURN:
            the construct table
    --]]
    function getType( name )
        return construct_types[name]
    end
    addon.construct.getType = getType


    local function errorModel( code, name, err )
        local message
        if code == 1 then message = "Non-existant construct" end
        if code == 2 then message = "Lua error" end
        if code == 3 then message = "Bad return" end
        if code == 4 then message = "Bad physics table" end
        if code == 5 then message = "Bad vertex table" end
        if code == 6 then message = "Triangulation failed" end

        local construct  = construct_types.error
        local result = construct.factory( param, construct.data, thread, physics )

        result.error = {
            code = code,
            name = name,
            lua = err,
            msg = message,
        }

        if CLIENT then
            result:Build( {} )
        end

        print( "-----------------------------" )
        PrintTable( result.error )
        print( "-----------------------------" )

        return result
    end

    local function getResult( construct, name, param, threaded, physics )
        local success, result = pcall( construct.factory, param, construct.data, threaded, physics )

        -- lua error, error model CODE 2
        if not success then
            return true, errorModel( 2, name, result )
        end

        -- Bad return, error model CODE 3
        if not istable( result ) then
            return true, errorModel( 3, name )
        end

        -- Bad physics table, error model CODE 4
        if physics and ( not istable( result.convexes ) or #result.convexes < 1 ) then
            return true, errorModel( 4, name )
        end

        if CLIENT then
            -- Bad vertex table, error model CODE 5
            if not istable( result.verts ) or #result.verts < 3 then
                return true, errorModel( 5, name )
            end

            if istable( result.index ) and not param.skip_tris then
                local suc, err = pcall( result.Build, result, param, threaded, physics )

                -- Triangulation failed, error model CODE 6
                if not suc or err or not istable( result.tris ) or #result.tris < 3 then
                    return true, errorModel( 6, name, err )
                end
            end
        else
            result.verts = nil
            result.index = nil
        end

        return true, result
    end


    --[[
        @FUNCTION: addon.construct.generate

        @DESCRIPTION:
            NOTE: Although this function can be called with a valid but unregistered construct, that should only be done
            for convenience while developing. Not registering the construct means other addons ( like prop2mesh )
            will not have quick access to it.

        @PARAMETERS:
            [table] construct
            [table] param      -- passed to the builder function
            [boolean] threaded -- return a coroutine (if possible)
            [boolean] physics  -- generate a collison model

        @RETURN:
            either a function or a coroutine that will build the mesh
    --]]
    function addon.construct.generate( construct, name, param, threaded, physics )
        -- Non-existant construct, error model CODE 1
        if construct == nil then
            return true, errorModel( 1, name )
        end

        name = construct.data.name or "NO_NAME"

        -- Expected yield: true, true, table
        if threaded and construct.data.canThread then
            return true, coroutine.create( function()
                coroutine_yield( getResult( construct, name, param, true, physics ) )
            end )
        end

        -- Expected return: true, table
        return getResult( construct, name, param, false, physics )
    end


    --[[
        @FUNCTION: addon.construct.get

        @DESCRIPTION:

        @PARAMETERS:
            [string] name
            [table] param      -- passed to the builder function
            [boolean] threaded -- return a coroutine (if possible)
            [boolean] physics  -- generate a collison model

        @RETURN:
            either a function or a coroutine that will build the mesh
    --]]
    function addon.construct.get( name, param, thread, physics )
        return addon.construct.generate( construct_types[name], name, param, thread, physics )
    end
end

local simpleton = addon.construct.simpleton
do
    local meta = {}
    meta.__index = meta


    --[[
        @FUNCTION: simpleton.New

        @DESCRIPTION: Create a new simpleton object, which is a table with a list of vertices and indices.

        @PARAMETERS:

        @RETURN:
            [table]
                [table] verts -- table containing all vertices
                [table] index -- table containing all triangle indices
                [table] key   -- used by the clipping engine to store original indices
    --]]
    function simpleton.New()
        return setmetatable( { verts = {}, index = {}, key = {} }, meta )
    end


    --[[
        @FUNCTION: simpleton.ClipPlane

        @DESCRIPTION: Create a new clipping plane

        @PARAMETERS:
            [vector] pos        - origin of  plane
            [vector] normal     - direction of plane
            [number] renderSize - display size of plane if drawn (optional)
            [color] renderColor - display color of plane if drawn (optional)

        @RETURN:
            [table]
                [vector] normal
                [vector] pos
                [table] verts
                [function] Draw

    --]]
    function simpleton.ClipPlane( pos, normal, renderSize, renderColor )
        vec_normalize( normal )

        local plane = {}

        plane.pos = pos
        plane.normal = normal
        plane.distance = -vec_dot( normal, pos )
        plane.renderColor = renderColor

        local v0 = normal:Angle():Up()
        local v1 = v0:Cross( normal )
        plane.verts = { pos + v0 * renderSize, pos + v1 * renderSize, pos - v0 * renderSize, pos - v1 * renderSize }

        plane.Draw = function( self )
            render.SetColorMaterial()
            render.DrawQuad( self.verts[1], self.verts[2], self.verts[3], self.verts[4], self.renderColor or color_white )
            render.DrawQuad( self.verts[4], self.verts[3], self.verts[2], self.verts[1], self.renderColor or color_white )
        end

        return plane
    end


    --[[
        @FUNCTION: simpleton:Merge

        @DESCRIPTION: Add the contents of one simpleton to another.

        @PARAMETERS:
            [simpleton] rhs

        @RETURN:
    --]]
    function meta:Merge( rhs )
        local key = {}
        local verts = rhs.verts
        local index = rhs.index

        for i = 1, #verts do
            key[i] = self:PushVertex( verts[i] )
        end

        for i = 1, #index do
            self:PushIndex( key[index[i]] )
        end
    end


    --[[
        @FUNCTION: simpleton:PushIndex

        @DESCRIPTION: Add a single index to the index table. NOTE, the builder requires triplets.

        @PARAMETERS:
            [number] n -- id of index

        @RETURN:
    --]]
    function meta:PushIndex( n )
        self.index[#self.index + 1] = n
    end


    --[[
        @FUNCTION: simpleton:PushTriangle

        @DESCRIPTION: Add a triangle consisting of 3 indexes to the index table.

        @PARAMETERS:
            [number] a -- first index
            [number] b -- second index
            [number] c -- third index

        @RETURN:
    --]]
    function meta:PushTriangle( a, b, c )
        self:PushIndex( a )
        self:PushIndex( b )
        self:PushIndex( c )
    end


    --[[
        @FUNCTION: simpleton:PushFace

        @DESCRIPTION: Triangulates a variable number of indices and adds each triplet to the index table.
                      NOTE, this creates a triangle fan, which only works for a convex face.
        @PARAMETERS:
            [number...] -- variadic arguments

        @RETURN:
    --]]
    function meta:PushFace( ... )
        local f = { ... }
        local a, b, c = f[1], f[2]

        for i = 3, #f do
            c = f[i]
            self:PushTriangle( a, b, c )
            b = c
        end
    end


    --[[
        @FUNCTION: simpleton:PushVertex

        @DESCRIPTION: Add a single vertex to the vertex table

        @PARAMETERS:
            [vector] v -- the vertex to add

        @RETURN:
            [number] -- the index of the added vertex
    --]]
    function meta:PushVertex( v )
        if not v then return end
        self.verts[#self.verts + 1] = Vector( v )
        return #self.verts
    end


    --[[
        @FUNCTION: simpleton:PushXYZ

        @DESCRIPTION: Add a single vertex to the vertex table, differs from PushVertex in that
                      PushVertex clones the passed vector.

        @PARAMETERS:
            [number] x
            [number] y
            [number] z

        @RETURN:
            [number] -- the index of the added vertex
    --]]
    function meta:PushXYZ( x, y, z )
        self.verts[#self.verts + 1] = Vector( x, y, z )
        return #self.verts
    end


    --[[
        @FUNCTION: simpleton:SetScale

        @DESCRIPTION: Multiplies every vertex by a vector

        @PARAMETERS:
            [vector] v -- the scale

        @RETURN:
    --]]
    function meta:SetScale( v )
        for i = 1, #self.verts do
            vec_mul( self.verts[i], v )
        end
    end


    --[[
        @FUNCTION: simpleton:Translate

        @DESCRIPTION: Translates every vertex by a vector

        @PARAMETERS:
            [vector] v -- the translation

        @RETURN:
    --]]
    function meta:Translate( v )
        for i = 1, #self.verts do
            vec_add( self.verts[i], v )
        end
    end


    --[[
        @FUNCTION: simpleton:Rotate

        @DESCRIPTION: Rotates every vertex by a vector

        @PARAMETERS:
            [angle] a -- the rotation

        @RETURN:
    --]]
    function meta:Rotate( a )
        for i = 1, #self.verts do
            vec_rotate( self.verts[i], a )
        end
    end


    --[[
        CLIPPING ENGINE
    ]]

    -- util.IntersectRayWithPlane seems to have an issue with the zero case
    local function intersectRayWithPlane( lineStart, lineDir, planePos, planeNormal )
        local a = vec_dot( planeNormal, lineDir )

        if a == 0 then
            if vec_dot( planeNormal, planePos - lineStart ) == 0 then
                return lineStart
            end
            return false
        end

        local d = vec_dot( planeNormal, planePos - lineStart )

        return lineStart + lineDir * ( d / a )
    end

    local function intersectSegmentWithPlane( lineStart, lineFinish, planePos, planeNormal )
        local lineDir = lineFinish - lineStart
        local xpoint = intersectRayWithPlane( lineStart, lineDir, planePos, planeNormal )

        if xpoint and vec_lengthsqr( xpoint - lineStart ) <= vec_lengthsqr( lineDir ) then
            return xpoint
        end

        return false
    end

    local function pushClippedTriangle( self, a, b, c )
        if not a or not b or not c then print( a, b, c ) return end

        local v0 = self.key[a]
        local v1 = self:PushVertex( b )
        local v2 = isvector( c ) and self:PushVertex( c ) or self.key[c]

        self:PushIndex( v0 )
        self:PushIndex( v1 )
        self:PushIndex( v2 )
    end

    local tempT, tempV, tempB = {}, {}, {}

    local function intersection( self, index, planePos, planeNormal, abovePlane, belowPlane )
        -- Temporarily store each index, vertex, and whether or not
        -- the abovePlane mesh contains the index.
        for i = 0, 2 do
            local n = self.index[index + i]
            tempT[i] = n
            tempV[i] = self.verts[n]
            tempB[i] = abovePlane.key[n] ~= nil
        end

        -- If all 3 indices are stored on the same side ( abovePlane or belowPlane ), there
        -- are no intersections, so the triangle is simply added to that side.
        if tempB[0] == tempB[1] and tempB[1] == tempB[2] then
            local side = tempB[0] and abovePlane or belowPlane

            side:PushIndex( side.key[tempT[0]] )
            side:PushIndex( side.key[tempT[1]] )
            side:PushIndex( side.key[tempT[2]] )

            return false
        end

        -- In every clipped triangle there will be one vertex that falls on the side opposite
        -- of the other two vertices. This vertex is used as the origin of the intersection checks. ( line AB, line AC )
        local tA = 2
        if tempB[0] ~= tempB[1] then tA = tempB[0] ~= tempB[2] and 0 or 1 end

        local tB = tA - 1
        if tB == -1 then tB = 2 end

        local tC = tA + 1
        if tC == 3 then tC = 0 end

        -- Perform a line-segment/plane intersectin between the two
        -- new edges and the clipping plane to get the new vertices.
        local instersect_tAB = intersectSegmentWithPlane( tempV[tA], tempV[tB], planePos, planeNormal )
        local instersect_tAC = intersectSegmentWithPlane( tempV[tA], tempV[tC], planePos, planeNormal )

        local side = tempB[tA] and abovePlane or belowPlane
        pushClippedTriangle( side, tempT[tA], instersect_tAC, instersect_tAB )

        local side = tempB[tB] and abovePlane or belowPlane
        pushClippedTriangle( side, tempT[tB], instersect_tAB, tempT[tC] )

        local side = tempB[tB] and abovePlane or belowPlane
        pushClippedTriangle( side, tempT[tC], instersect_tAB, instersect_tAC )

        -- The new vertices are also returned to be used for whatever later on
        if tempB[tA] then
            return instersect_tAB, instersect_tAC
        else
            return instersect_tAC, instersect_tAB
        end
    end

    local function closeLineLoop( abovePlane, belowPlane, loopCenter, loopPoints )
        local aA = abovePlane:PushVertex( loopCenter )
        local bA = belowPlane:PushVertex( loopCenter )

        local wrap = { [#loopPoints] = 1 }

        for i = 1, #loopPoints do
            local p0 = loopPoints[i]
            local p1 = loopPoints[wrap[i] or i + 1]

            abovePlane:PushTriangle( aA, abovePlane:PushVertex( p0 ), abovePlane:PushVertex( p1 ) )
            belowPlane:PushTriangle( bA, belowPlane:PushVertex( p1 ), belowPlane:PushVertex( p0 ) )
        end
    end


    --[[
        @FUNCTION: simpleton:Bisect

        @DESCRIPTION: Cut a simpleton along a plane

        @PARAMETERS:
            [table] plane -- the plane should have a pos and normal field

        @RETURN:
            [table] abovePlane simpleton
            [table] belowPlane simpleton
    --]]
    function meta:Bisect( plane, fill )
        -- Separate original vertices into two tables, determined by
        -- which side of clipping plane they are on.
        -- Store the original index of each vertex in the key table [ original = new ].
        local abovePlane = simpleton.New()
        local belowPlane = simpleton.New()

        local planePos = plane.pos
        local planeNormal = plane.normal

        for i = 1, #self.verts do
            if vec_dot( planeNormal, self.verts[i] - planePos ) >= 1e-6 then
                abovePlane.key[i] = abovePlane:PushVertex( self.verts[i] )
            else
                belowPlane.key[i] = belowPlane:PushVertex( self.verts[i] )
            end
        end

        -- If either mesh has a vertex count of 0, there are no
        -- intersections and we can stop here.
        if #abovePlane.verts == 0 or #belowPlane.verts == 0 then
            return false
        end

        -- Check each edge of each triangle for an intersection with the plane.
        -- All that intersect are split into two smaller triangles.
        local loopCenter = Vector()
        local loopPoints = {}

        for i = 1, #self.index, 3 do
            local l0, l1 = intersection( self, i, planePos, planeNormal, abovePlane, belowPlane )

            if fill and l0 and l1 then
                vec_add( loopCenter, l0 )
                loopPoints[#loopPoints + 1] = l0
            end
        end

        if fill then
            loopCenter = loopCenter / #loopPoints

            table.sort( loopPoints, function( sa, sb )
                return vec_dot( planeNormal, vec_cross( sa - loopCenter, sb - loopCenter ) ) < 0
            end )

            closeLineLoop( abovePlane, belowPlane, loopCenter, loopPoints )
        end

        abovePlane.key = {}
        belowPlane.key = {}

        return abovePlane, belowPlane
    end


    if CLIENT then
        local YIELD_THRESHOLD = 30

        local function calcUV( a, b, c, scale )
            local euler = vec_angle( a.normal )

            local coord = WorldToLocal( a.pos, ang, vec, euler )
            a.u = coord.y * scale
            a.v = coord.z * scale

            local coord = WorldToLocal( b.pos, ang, vec, euler )
            b.u = coord.y * scale
            b.v = coord.z * scale

            local coord = WorldToLocal( c.pos, ang, vec, euler )
            c.u = coord.y * scale
            c.v = coord.z * scale
        end

        local function calcInside( verts, threaded )
            for i = #verts, 1, -1 do
                local v = verts[i]
                verts[#verts + 1] = { pos = v.pos, normal = -v.normal, u = v.u, v = v.v, userdata = v.userdata }

                if threaded and ( i % YIELD_THRESHOLD == 0 ) then coroutine_yield( false ) end
            end
        end

        local function calcBounds( vertex, mins, maxs )
            local x = vertex.x
            local y = vertex.y
            local z = vertex.z
            if x < mins.x then mins.x = x elseif x > maxs.x then maxs.x = x end
            if y < mins.y then mins.y = y elseif y > maxs.y then maxs.y = y end
            if z < mins.z then mins.z = z elseif z > maxs.z then maxs.z = z end
        end

        local function calcNormals( verts, deg, threaded )
            -- credit to Sevii for this craziness
            deg = math_cos( math_rad( deg ) )

            local norms = setmetatable( {}, { __index = function( t, k ) local r = setmetatable( {}, { __index = function( t, k ) local r = setmetatable( {}, { __index = function( t, k ) local r = {} t[k] = r return r end } ) t[k] = r return r end } ) t[k] = r return r end } )

            for i = 1, #verts do
                local vertex = verts[i]
                local pos = vertex.pos
                local norm = norms[pos[1]][pos[2]][pos[3]]
                norm[#norm + 1] = vertex.normal

                if threaded and ( i % YIELD_THRESHOLD == 0 ) then coroutine_yield( false ) end
            end

            for i = 1, #verts do
                local vertex = verts[i]
                local normal = Vector()
                local count = 0
                local pos = vertex.pos

                local nk = norms[pos[1]][pos[2]][pos[3]]
                for j = 1, #nk do
                    local norm = nk[j]
                    if vec_dot( vertex.normal, norm ) >= deg then
                        vec_add( normal, norm )
                        count = count + 1
                    end
                end

                if count > 1 then
                    vec_div( normal, count )
                    vertex.normal = normal
                end

                if threaded and ( i % YIELD_THRESHOLD == 0 ) then coroutine_yield( false ) end
            end
        end

        local function calcTangents( verts, threaded )
            -- credit to https://gamedev.stackexchange.com/questions/68612/how-to-compute-tangent-and-bitangent-vectors
            -- seems to work but i have no idea how or why, nor why i cant do this during triangulation

            local tan1 = {}
            local tan2 = {}

            for i = 1, #verts do
                tan1[i] = Vector( 0, 0, 0 )
                tan2[i] = Vector( 0, 0, 0 )

                if threaded and ( i % YIELD_THRESHOLD == 0 ) then coroutine_yield( false ) end
            end

            for i = 1, #verts - 2, 3 do
                local v1 = verts[i]
                local v2 = verts[i + 1]
                local v3 = verts[i + 2]

                local p1 = v1.pos
                local p2 = v2.pos
                local p3 = v3.pos

                local x1 = p2.x - p1.x
                local x2 = p3.x - p1.x
                local y1 = p2.y - p1.y
                local y2 = p3.y - p1.y
                local z1 = p2.z - p1.z
                local z2 = p3.z - p1.z

                local us1 = v2.u - v1.u
                local us2 = v3.u - v1.u
                local ut1 = v2.v - v1.v
                local ut2 = v3.v - v1.v

                local r = 1 / ( us1 * ut2 - us2 * ut1 )

                local sdir = Vector( ( ut2 * x1 - ut1 * x2 ) * r, ( ut2 * y1 - ut1 * y2 ) * r, ( ut2 * z1 - ut1 * z2 ) * r )
                local tdir = Vector( ( us1 * x2 - us2 * x1 ) * r, ( us1 * y2 - us2 * y1 ) * r, ( us1 * z2 - us2 * z1 ) * r )

                vec_add( tan1[i], sdir )
                vec_add( tan1[i + 1], sdir )
                vec_add( tan1[i + 2], sdir )

                vec_add( tan2[i], tdir )
                vec_add( tan2[i + 1], tdir )
                vec_add( tan2[i + 2], tdir )

                if threaded and ( i % YIELD_THRESHOLD == 0 ) then coroutine_yield( false ) end
            end

            for i = 1, #verts do
                local n = verts[i].normal
                local t = tan1[i]

                local tangent = ( t - n * vec_dot( n, t ) )
                vec_normalize( tangent )

                verts[i].userdata = { tangent[1], tangent[2], tangent[3], vec_dot( vec_cross( n, t ), tan2[i] ) }

                if threaded and ( i % YIELD_THRESHOLD == 0 ) then coroutine_yield( false ) end
            end
        end

        local ENUM_TANGENTS = 1
        local ENUM_INSIDE = 2
        local ENUM_INVERT = 4


        --[[
            @FUNCTION: simpleton:Build

            @DESCRIPTION: Convert a simpleton into imesh vertex structure

            @PARAMETERS:

            @RETURN:
                [table] imesh vertex struct
        --]]
        function meta:Build( param, threaded, physics )
            --[[
                CONFIG

                if necessary, other addons ( like prop2mesh ) can override flags by setting the skip params
                    .skip_bounds
                    .skip_tangents
                    .skip_inside
                    .skip_invert
                    .skip_uv
                    .skip_normals
            ]]

            local fbounds, ftangents, finside, finvert

            local mins, maxs
            if not param.skip_bounds then

                -- if physics are generated we can use GetCollisionBounds for SetRenderBounds
                -- otherwise we need to get mins and maxs manually

                if not physics then
                    mins = Vector( math.huge, math.huge, math.huge )
                    maxs = Vector( -math.huge, -math.huge, -math.huge )

                    fbounds = true
                end
            end

            local bits = tonumber( param.PrimMESHENUMS ) or 0

            if not param.skip_tangents then
                if system.IsLinux() or system.IsOSX() then ftangents = true else ftangents = bit.band( bits, ENUM_TANGENTS ) == ENUM_TANGENTS end
            end

            if not param.skip_inside then
                finside = bit.band( bits, ENUM_INSIDE ) == ENUM_INSIDE
            end

            if not param.skip_invert then
                finvert = bit.band( bits, ENUM_INVERT ) == ENUM_INVERT
            end

            local uvmap
            if not param.skip_uv then
                uvmap = tonumber( param.PrimMESHUV ) or 48
                if uvmap < 8 then uvmap = 8 end
                uvmap = 1 / uvmap
            end

            -- TRIANGULATE
            self.tris = {}

            local tris  = self.tris
            local verts = self.verts
            local index = self.index

            for i = 1, #index, 3 do
                local p0 = verts[index[i]]
                local p1 = verts[index[i + 2]]
                local p2 = verts[index[i + 1]]

                local normal = vec_cross( p2 - p0, p1 - p0 )
                vec_normalize( normal )

                local v0 = { pos = Vector( finvert and p2 or p0 ), normal = Vector( normal ) }
                local v1 = { pos = Vector( p1 ), normal = Vector( normal ) }
                local v2 = { pos = Vector( finvert and p0 or p2 ), normal = Vector( normal ) }

                if uvmap then calcUV( v0, v1, v2, uvmap ) end

                tris[#tris + 1] = v0
                tris[#tris + 1] = v1
                tris[#tris + 1] = v2

                if threaded and ( i % YIELD_THRESHOLD == 0 ) then coroutine_yield( false ) end
            end

            -- POSTPROCESS
            if not param.skip_normals then
                local smooth = tonumber( param.PrimMESHSMOOTH ) or 0
                if smooth ~= 0 then
                    calcNormals( tris, smooth, threaded )
                end
            end

            if ftangents then
                calcTangents( tris, threaded )
            end

            if finside then
                calcInside( tris, threaded )
            end

            if fbounds then
                self.mins = mins
                self.maxs = maxs
            end
        end
    end
end


-- UTIL
local function map( x, in_min, in_max, out_min, out_max )
    return ( x - in_min ) * ( out_max - out_min ) / ( in_max - in_min ) + out_min
end

local function transform( verts, rotate, offset, thread )
    --[[
        NOTE: Vectors are mutable objects, which means this may have unexpected results if used
        incorrectly ( applying transform to same vertex multiple times by mistake ).That's why it's
        per construct, instead of in the global getter function.
    ]]
    if isangle( rotate ) and ( rotate.p ~= 0 or rotate.y ~= 0 or rotate.r ~= 0 ) then
        for i = 1, #verts do
            vec_rotate( verts[i], rotate )
        end
    end

    if isvector( offset ) and ( offset.x ~= 0 or offset.y ~= 0 or offset.z ~= 0 ) then
        for i = 1, #verts do
            vec_add( verts[i], offset )
        end
    end
end


-- ERROR
registerType( "error", function( param, data, threaded, physics )
    local model = simpleton.New()

    model:PushXYZ( 12, -12, -12 )
    model:PushXYZ( 12, 12, -12 )
    model:PushXYZ( 12, 12, 12 )
    model:PushXYZ( 12, -12, 12 )
    model:PushXYZ( -12, -12, -12 )
    model:PushXYZ( -12, 12, -12 )
    model:PushXYZ( -12, 12, 12 )
    model:PushXYZ( -12, -12, 12 )

    if CLIENT then
        model:PushFace( 1, 2, 3, 4 )
        model:PushFace( 2, 6, 7, 3 )
        model:PushFace( 6, 5, 8, 7 )
        model:PushFace( 5, 1, 4, 8 )
        model:PushFace( 4, 3, 7, 8 )
        model:PushFace( 5, 6, 2, 1 )
    end

    model.convexes = { model.verts }

    return model
end )


-- CONE
registerType( "cone", function( param, data, threaded, physics )
    local maxseg = param.PrimMAXSEG or 32
    if maxseg < 3 then maxseg = 3 elseif maxseg > 32 then maxseg = 32 end
    local numseg = param.PrimNUMSEG or 32
    if numseg < 1 then numseg = 1 elseif numseg > maxseg then numseg = maxseg end

    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5

    local tx = map( param.PrimTX or 0, -1, 1, -2, 2 )
    local ty = map( param.PrimTY or 0, -1, 1, -2, 2 )

    local model = simpleton.New()
    local verts = model.verts

    for i = 0, numseg do
        local a = math_rad( ( i / maxseg ) * -360 )
        model:PushXYZ( math_sin( a ) * dx, math_cos( a ) * dy, -dz )
    end

    local c0 = #verts
    local c1 = c0 + 1
    local c2 = c0 + 2

    model:PushXYZ( 0, 0, -dz )
    model:PushXYZ( -dx * tx, dy * ty, dz )

    if CLIENT then
        for i = 1, c0 - 1 do
            model:PushTriangle( i, i + 1, c2 )
            model:PushTriangle( i, c1, i + 1 )
        end
        if numseg ~= maxseg then
            model:PushTriangle( c0, c1, c2 )
            model:PushTriangle( c0 + 1, 1, c2 )
        end
    end

    if physics then
        local convexes

        if numseg ~= maxseg then
            convexes = {
                { verts[c1], verts[c2] },
                { verts[c1], verts[c2] },
            }

            for i = 1, c0 do
                if ( i - 1 <= maxseg * 0.5 ) then
                    table_insert( convexes[1], verts[i] )
                end
                if ( i - 0 >= maxseg * 0.5 ) then
                    table_insert( convexes[2], verts[i] )
                end
            end
        else
            convexes = { verts }
        end

        model.convexes = convexes
    end

    transform( verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- CUBE
registerType( "cube", function( param, data, threaded, physics )
    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5

    local tx = 1 - ( param.PrimTX or 0 )
    local ty = 1 - ( param.PrimTY or 0 )

    local model = simpleton.New()

    if tx == 0 and ty == 0 then
        model:PushXYZ( dx, -dy, -dz )
        model:PushXYZ( dx, dy, -dz )
        model:PushXYZ( -dx, -dy, -dz )
        model:PushXYZ( -dx, dy, -dz )
        model:PushXYZ( 0, 0, dz )

        if CLIENT then
            model:PushTriangle( 1, 2, 5 )
            model:PushTriangle( 2, 4, 5 )
            model:PushTriangle( 4, 3, 5 )
            model:PushTriangle( 3, 1, 5 )
            model:PushFace( 3, 4, 2, 1 )
        end
    else
        model:PushXYZ( dx, -dy, -dz )
        model:PushXYZ( dx, dy, -dz )
        model:PushXYZ( dx * tx, dy * ty, dz )
        model:PushXYZ( dx * tx, -dy * ty, dz )
        model:PushXYZ( -dx, -dy, -dz )
        model:PushXYZ( -dx, dy, -dz )
        model:PushXYZ( -dx * tx, dy * ty, dz )
        model:PushXYZ( -dx * tx, -dy * ty, dz )

        if CLIENT then
            model:PushFace( 1, 2, 3, 4 )
            model:PushFace( 2, 6, 7, 3 )
            model:PushFace( 6, 5, 8, 7 )
            model:PushFace( 5, 1, 4, 8 )
            model:PushFace( 4, 3, 7, 8 )
            model:PushFace( 5, 6, 2, 1 )
        end
    end

    if physics then model.convexes = { model.verts } end

    transform( model.verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- CUBE_MAGIC
registerType( "cube_magic", function( param, data, threaded, physics )
    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5

    local tx = 1 - ( param.PrimTX or 0 )
    local ty = 1 - ( param.PrimTY or 0 )

    local dt = math_min( param.PrimDT or 1, dx, dy )

    if dt == dx or dt == dy then -- simple diff check is not correct, should be sine of taper angle?
        local construct = construct_types.cube
        return construct.factory( param, construct.data, threaded, physics )
    end

    local sides
    for i = 1, 6 do
        local flag = bit.lshift( 1, i - 1 )
        local bits = bit.band( tonumber( param.PrimSIDES ) or 0, flag ) == flag

        if bits then
            if not sides then sides = {} end
            sides[i] = true
        end
    end

    if not sides then sides = { true, true, true, true, true, true } end

    local normals = {
        Vector( 1, 0, 0 ):Angle(),
        Vector( -1, 0, 0 ):Angle(),
        Vector( 0, 1, 0 ):Angle(),
        Vector( 0, -1, 0 ):Angle(),
        Vector( 0, 0, 1 ):Angle(),
        Vector( 0, 0, -1 ):Angle(),
    }

    local a = Vector( 1, -1, -1 )
    local b = Vector( 1, 1, -1 )
    local c = Vector( 1, 1, 1 )
    local d = Vector( 1, -1, 1 )

    local model = simpleton.New()
    local verts = model.verts

    local convexes
    if physics then
        convexes = {}
        model.convexes = convexes
    end

    local ibuffer = 1

    for k, v in ipairs( normals ) do
        if not sides[k] then
            ibuffer = ibuffer - 8
        else
            local pos = Vector( a )
            vec_rotate( pos, v )

            pos.x = pos.x * dx
            pos.y = pos.y * dy
            pos.z = pos.z * dz

            if pos.z > 0 then
                pos.x = pos.x * tx
                pos.y = pos.y * ty
            end

            model:PushVertex( pos )
            model:PushVertex( pos - vec_getnormalized( pos ) * dt )

            local pos = Vector( b )
            vec_rotate( pos, v )

            pos.x = pos.x * dx
            pos.y = pos.y * dy
            pos.z = pos.z * dz

            if pos.z > 0 then
                pos.x = pos.x * tx
                pos.y = pos.y * ty
            end

            model:PushVertex( pos )
            model:PushVertex( pos - vec_getnormalized( pos ) * dt )

            local pos = Vector( c )
            vec_rotate( pos, v )

            pos.x = pos.x * dx
            pos.y = pos.y * dy
            pos.z = pos.z * dz

            if pos.z > 0 then
                pos.x = pos.x * tx
                pos.y = pos.y * ty
            end

            model:PushVertex( pos )
            model:PushVertex( pos - vec_getnormalized( pos ) * dt )

            local pos = Vector( d )
            vec_rotate( pos, v )

            pos.x = pos.x * dx
            pos.y = pos.y * dy
            pos.z = pos.z * dz

            if pos.z > 0 then
                pos.x = pos.x * tx
                pos.y = pos.y * ty
            end

            model:PushVertex( pos )
            model:PushVertex( pos - vec_getnormalized( pos ) * dt )

            if physics then
                local count = #verts
                convexes[#convexes + 1] = {
                    verts[count - 0],
                    verts[count - 1],
                    verts[count - 2],
                    verts[count - 3],
                    verts[count - 4],
                    verts[count - 5],
                    verts[count - 6],
                    verts[count - 7],
                }
            end

            if CLIENT then
                local n = ( k - 1 ) * 8 + ibuffer
                model:PushFace( n + 0, n + 2, n + 4, n + 6 )
                model:PushFace( n + 3, n + 1, n + 7, n + 5 )
                model:PushFace( n + 1, n + 0, n + 6, n + 7 )
                model:PushFace( n + 2, n + 3, n + 5, n + 4 )
                model:PushFace( n + 5, n + 7, n + 6, n + 4 )
                model:PushFace( n + 0, n + 1, n + 3, n + 2 )
            end
        end
    end

    transform( verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- CUBE_HOLE
registerType( "cube_hole", function( param, data, threaded, physics )
    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5
    local dt = math_min( param.PrimDT or 1, dx, dy )

    if dt == dx or dt == dy then
        local construct = construct_types.cube
        return construct.factory( param, construct.data, threaded, physics )
    end

    local numseg = param.PrimNUMSEG or 4
    if numseg > 4 then numseg = 4 elseif numseg < 1 then numseg = 1 end

    local numring = 4 * math_round( ( param.PrimSUBDIV or 32 ) / 4 )
    if numring < 4 then numring = 4 elseif numring > 32 then numring = 32 end

    local cube_angle = Angle( 0, 90, 0 )
    local cube_corner0 = Vector( 1, 0, 0 )
    local cube_corner1 = Vector( 1, 1, 0 )
    local cube_corner2 = Vector( 0, 1, 0 )

    local ring_steps0 = numring / 4
    local ring_steps1 = numring / 2
    local capped = numseg ~= 4

    local model = simpleton.New()
    local verts = model.verts

    if CLIENT and capped then
        model:PushFace( 8, 7, 1, 4 )
    end

    if physics then
        convexes = {}
        model.convexes = convexes
    end

    for i = 0, numseg - 1 do
        vec_rotate( cube_corner0, cube_angle )
        vec_rotate( cube_corner1, cube_angle )
        vec_rotate( cube_corner2, cube_angle )

        local part
        if physics then part = {} end

        model:PushXYZ( cube_corner0.x * dx, cube_corner0.y * dy, -dz )
        model:PushXYZ( cube_corner1.x * dx, cube_corner1.y * dy, -dz )
        model:PushXYZ( cube_corner2.x * dx, cube_corner2.y * dy, -dz )
        model:PushXYZ( cube_corner0.x * dx, cube_corner0.y * dy, dz )
        model:PushXYZ( cube_corner1.x * dx, cube_corner1.y * dy, dz )
        model:PushXYZ( cube_corner2.x * dx, cube_corner2.y * dy, dz )

        local count_end0 = #verts
        if CLIENT then
            model:PushFace( count_end0 - 5, count_end0 - 4, count_end0 - 1, count_end0 - 2 )
            model:PushFace( count_end0 - 4, count_end0 - 3, count_end0 - 0, count_end0 - 1 )
        end

        local ring_angle = -i * 90
        for j = 0, ring_steps0 do
            local a = math_rad( ( j / numring ) * -360 + ring_angle )
            model:PushXYZ( math_sin( a ) * ( dx - dt ), math_cos( a ) * ( dy - dt ), -dz )
            model:PushXYZ( math_sin( a ) * ( dx - dt ), math_cos( a ) * ( dy - dt ), dz )
        end

        local count_end1 = #verts
        if physics then
            convexes[#convexes + 1] = {
                verts[count_end0 - 0],
                verts[count_end0 - 3],
                verts[count_end0 - 4],
                verts[count_end0 - 1],
                verts[count_end1 - 0],
                verts[count_end1 - 1],
                verts[count_end1 - ring_steps1 * 0.5],
                verts[count_end1 - ring_steps1 * 0.5 - 1],
            }
            convexes[#convexes + 1] = {
                verts[count_end0 - 2],
                verts[count_end0 - 5],
                verts[count_end0 - 4],
                verts[count_end0 - 1],
                verts[count_end1 - ring_steps1],
                verts[count_end1 - ring_steps1 - 1],
                verts[count_end1 - ring_steps1 * 0.5],
                verts[count_end1 - ring_steps1 * 0.5 - 1],
            }
        end

        if CLIENT then
            model:PushTriangle( count_end0 - 1, count_end0 - 0, count_end1 - 0 )
            model:PushTriangle( count_end0 - 1, count_end1 - ring_steps1, count_end0 - 2 )
            model:PushTriangle( count_end0 - 4, count_end1 - 1, count_end0 - 3 )
            model:PushTriangle( count_end0 - 4, count_end0 - 5, count_end1 - ring_steps1 - 1 )

            for j = 0, ring_steps0 - 1 do
                local count_end2 = count_end1 - j * 2
                model:PushTriangle( count_end0 - 1, count_end2, count_end2 - 2 )
                model:PushTriangle( count_end0 - 4, count_end2 - 3, count_end2 - 1 )
                model:PushFace( count_end2, count_end2 - 1, count_end2 - 3, count_end2 - 2 )
            end

            if capped and i == numseg  - 1 then
                model:PushFace( count_end0, count_end0 - 3, count_end1 - 1, count_end1 )
            end
        end
    end

    transform( verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- CUBE_CYLINDER
registerType( "cylinder", function( param, data, threaded, physics )
    local maxseg = param.PrimMAXSEG or 32
    if maxseg < 3 then maxseg = 3 elseif maxseg > 32 then maxseg = 32 end
    local numseg = param.PrimNUMSEG or 32
    if numseg < 1 then numseg = 1 elseif numseg > maxseg then numseg = maxseg end

    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5

    local tx = 1 - ( param.PrimTX or 0 )
    local ty = 1 - ( param.PrimTY or 0 )

    local model = simpleton.New()
    local verts = model.verts

    if tx == 0 and ty == 0 then
        for i = 0, numseg do
            local a = math_rad( ( i / maxseg ) * -360 )
            model:PushXYZ( math_sin( a ) * dx, math_cos( a ) * dy, -dz )
        end
    else
        for i = 0, numseg do
            local a = math_rad( ( i / maxseg ) * -360 )
            model:PushXYZ( math_sin( a ) * dx, math_cos( a ) * dy, -dz )
            model:PushXYZ( math_sin( a ) * ( dx * tx ), math_cos( a ) * ( dy * ty ), dz )
        end
    end

    local c0 = #verts
    local c1 = c0 + 1
    local c2 = c0 + 2

    model:PushXYZ( 0, 0, -dz )
    model:PushXYZ( 0, 0, dz )

    if CLIENT then
        if tx == 0 and ty == 0 then
            for i = 1, c0 - 1 do
                model:PushTriangle( i, i + 1, c2 )
                model:PushTriangle( i, c1, i + 1 )
            end

            if numseg ~= maxseg then
                model:PushTriangle( c0, c1, c2 )
                model:PushTriangle( c0 + 1, 1, c2 )
            end
        else
            for i = 1, c0 - 2, 2 do
                model:PushFace( i, i + 2, i + 3, i + 1 )
                model:PushTriangle( i, c1, i + 2 )
                model:PushTriangle( i + 1, i + 3, c2 )
            end

            if numseg ~= maxseg then
                model:PushFace( c1, c2, c0, c0 - 1 )
                model:PushFace( c1, 1, 2, c2 )
            end
        end
    end

    if physics then
        local convexes

        if numseg ~= maxseg then
            convexes = {
                { verts[c1], verts[c2] },
                { verts[c1], verts[c2] },
            }

            if tx == 0 and ty == 0 then
                for i = 1, c0 do
                    if ( i - 1 <= maxseg * 0.5 ) then
                        table_insert( convexes[1], verts[i] )
                    end
                    if ( i - 1 >= maxseg * 0.5 ) then
                        table_insert( convexes[2], verts[i] )
                    end
                end
            else
                for i = 1, c0 do
                    if i - ( maxseg > 3 and 2 or 1 ) <= maxseg then
                        table_insert( convexes[1], verts[i] )
                    end
                    if i - 1 >= maxseg then
                        table_insert( convexes[2], verts[i] )
                    end
                end
            end
        else
            convexes = { verts }
        end

        model.convexes = convexes
    end

    transform( verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- DOME
registerType( "dome", function( param, data, threaded, physics )

    return construct_types.sphere.factory( param, data, threaded, physics )

end, { canThread = true, domePlane = { pos = Vector(), normal = Vector( 0, 0, 1 ) } } )


-- PYRAMID
registerType( "pyramid", function( param, data, threaded, physics )
    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5

    local tx = map( param.PrimTX or 0, -1, 1, -2, 2 )
    local ty = map( param.PrimTY or 0, -1, 1, -2, 2 )

    local model = simpleton.New()

    model:PushXYZ( dx, -dy, -dz )
    model:PushXYZ( dx, dy, -dz )
    model:PushXYZ( -dx, -dy, -dz )
    model:PushXYZ( -dx, dy, -dz )
    model:PushXYZ( -dx * tx, dy * ty, dz )

    if CLIENT then
        model:PushTriangle( 1, 2, 5 )
        model:PushTriangle( 2, 4, 5 )
        model:PushTriangle( 4, 3, 5 )
        model:PushTriangle( 3, 1, 5 )
        model:PushTriangle( 3, 4, 2 )
        model:PushTriangle( 3, 2, 1 )
    end

    if physics then
        model.convexes = { model.verts }
    end

    transform( model.verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- SPHERE
local function MakeSphere( model, subdiv, dx, dy, dz, threaded )
    for y = 0, subdiv do
        local v = y / subdiv
        local t = v * math_pi

        local cosPi = math_cos( t )
        local sinPi = math_sin( t )

        for x = 0, subdiv  do
            local u = x / subdiv
            local p = u * math_tau

            local cosTau = math_cos( p )
            local sinTau = math_sin( p )

            model:PushXYZ( -dx * cosTau * sinPi, dy * sinTau * sinPi, dz * cosPi )
        end

        if y > 0 then
            local i = #model.verts - 2 * ( subdiv + 1 )

            while ( i + subdiv + 2 ) < #model.verts do
                model:PushFace( i + 1, i + 2, i + subdiv + 3, i + subdiv + 2 )
                i = i + 1
            end
        end
    end
end

registerType( "sphere", function( param, data, threaded, physics )
    local subdiv = 2 * math_round( ( param.PrimSUBDIV or 32 ) / 2 )
    if subdiv < 4 then subdiv = 4 elseif subdiv > 32 then subdiv = 32 end

    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5

    local domePlane = data.domePlane

    local model = simpleton.New()

    if CLIENT then
        MakeSphere( model, subdiv, dx, dy, dz, threaded )

        if domePlane then
            model, _ = model:Bisect( domePlane, true )
        end

        transform( model.verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

        if physics then
            if subdiv <= 8 then
                model.convexes = { model.verts } -- no need to recompute the sphere if subdivisions are not clamped
            else
                local convex = simpleton.New()
                MakeSphere( convex, 8, dx, dy, dz, threaded )

                if domePlane then
                    convex, _ = convex:Bisect( domePlane, true )
                end

                model.convexes = { convex.verts }

                transform( convex.verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )
            end
        end
    else
        if physics then
            MakeSphere( model, math_min( subdiv, 8 ), dx, dy, dz, threaded )

            if domePlane then
                model, _ = model:Bisect( domePlane, true )
            end

            model.convexes = { model.verts }

            transform( model.verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )
        end
    end

    return model

end, { canThread = true } )


-- TORUS
registerType( "torus", function( param, data, threaded, physics )
    local maxseg = param.PrimMAXSEG or 32
    if maxseg < 3 then maxseg = 3 elseif maxseg > 32 then maxseg = 32 end
    local numseg = param.PrimNUMSEG or 32
    if numseg < 1 then numseg = 1 elseif numseg > maxseg then numseg = maxseg end
    local numring = param.PrimSUBDIV or 16
    if numring < 3 then numring = 3 elseif numring > 32 then numring = 32 end

    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5
    local dt = math_min( ( param.PrimDT or 1 ) * 0.5, dx, dy )

    if dt == dx or dt == dy then
    end

    local model = simpleton.New()

    if CLIENT then
        for j = 0, numring do
            for i = 0, maxseg do
                local u = i / maxseg * math_tau
                local v = j / numring * math_tau
                model:PushXYZ( ( dx + dt * math_cos( v ) ) * math_cos( u ), ( dy + dt * math_cos( v ) ) * math_sin( u ), dz * math_sin( v ) )
            end
        end

        for j = 1, numring do
            for i = 1, numseg do
                model:PushFace( ( maxseg + 1 ) * j + i, ( maxseg + 1 ) * ( j - 1 ) + i, ( maxseg + 1 ) * ( j - 1 ) + i + 1, ( maxseg + 1 ) * j + i + 1 )
            end
        end

        if numseg ~= maxseg then
            local cap1 = {}
            local cap2 = {}

            for j = 1, numring do
                cap1[#cap1 + 1] = ( maxseg + 1 ) * j + 1
                cap2[#cap2 + 1] = ( maxseg + 1 ) * ( numring - j ) + numseg + 1
            end

            model:PushFace( unpack( cap1 ) )
            model:PushFace( unpack( cap2 ) )
        end

        transform( model.verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )
    end

    if physics then
        local numring = math_min( 4, numring ) -- we want a lower detailed convexes model

        local convex = simpleton.New()
        local pverts = convex.verts

        for j = 0, numring do
            for i = 0, maxseg do
                local u = i / maxseg * math_tau
                local v = j / numring * math_tau
                convex:PushXYZ( ( dx + dt * math_cos( v ) ) * math_cos( u ), ( dy + dt * math_cos( v ) ) * math_sin( u ), dz * math_sin( v ) )
            end
        end

        local convexes = {}
        model.convexes = convexes

        for j = 1, numring do
            for i = 1, numseg do
                if not convexes[i] then
                    convexes[i] = {}
                end
                local part = convexes[i]
                part[#part + 1] = pverts[( maxseg + 1 ) * j + i]
                part[#part + 1] = pverts[( maxseg + 1 ) * ( j - 1 ) + i]
                part[#part + 1] = pverts[( maxseg + 1 ) * ( j - 1 ) + i + 1]
                part[#part + 1] = pverts[( maxseg + 1 ) * j + i + 1]
            end
        end

        transform( pverts, param.PrimMESHROT, param.PrimMESHPOS, threaded )
    end

    return model
end, { canthread = true } )


-- TUBE
registerType( "tube", function( param, data, threaded, physics )
    local verts, faces, convexes

    local maxseg = param.PrimMAXSEG or 32
    if maxseg < 3 then maxseg = 3 elseif maxseg > 32 then maxseg = 32 end
    local numseg = param.PrimNUMSEG or 32
    if numseg < 1 then numseg = 1 elseif numseg > maxseg then numseg = maxseg end

    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5
    local dt = math_min( param.PrimDT or 1, dx, dy )

    if dt == dx or dt == dy then -- MAY NEED TO REFACTOR THIS IN THE FUTURE IF CYLINDER MODIFIERS ARE CHANGED
        local construct = construct_types.cylinder
        return construct.factory( param, construct.data, threaded, physics )
    end

    local tx = 1 - ( param.PrimTX or 0 )
    local ty = 1 - ( param.PrimTY or 0 )
    local iscone = tx == 0 and ty == 0

    local model = simpleton.New()
    local verts = model.verts

    if iscone then
        for i = 0, numseg do
            local a = math_rad( ( i / maxseg ) * -360 )
            model:PushXYZ( math_sin( a ) * dx, math_cos( a ) * dy, -dz )
            model:PushXYZ( math_sin( a ) * ( dx - dt ), math_cos( a ) * ( dy - dt ), -dz )
        end
    else
        for i = 0, numseg do
            local a = math_rad( ( i / maxseg ) * -360 )
            model:PushXYZ( math_sin( a ) * dx, math_cos( a ) * dy, -dz )
            model:PushXYZ( math_sin( a ) * ( dx * tx ), math_cos( a ) * ( dy * ty ), dz )
            model:PushXYZ( math_sin( a ) * ( dx - dt ), math_cos( a ) * ( dy - dt ), -dz )
            model:PushXYZ( math_sin( a ) * ( ( dx - dt ) * tx ), math_cos( a ) * ( ( dy - dt ) * ty ), dz )
        end
    end

    local c0 = #verts
    local c1 = c0 + 1
    local c2 = c0 + 2

    model:PushXYZ( 0, 0, -dz )
    model:PushXYZ( 0, 0, dz )

    if CLIENT then
        if iscone then
            for i = 1, c0 - 2, 2 do
                model:PushFace( i + 3, i + 2, i + 0, i + 1 ) -- bottom
                model:PushTriangle( i + 0, i + 2, c2 ) -- outside
                model:PushTriangle( i + 3, i + 1, c2 ) -- inside
            end

            if numseg ~= maxseg then
                local i = numseg * 2 + 1
                model:PushTriangle( i, i + 1, c2 )
                model:PushTriangle( 2, 1, c2 )
            end
        else
            for i = 1, c0 - 4, 4 do
                model:PushFace( i + 0, i + 2, i + 6, i + 4 ) -- bottom
                model:PushFace( i + 4, i + 5, i + 1, i + 0 ) -- outside
                model:PushFace( i + 2, i + 3, i + 7, i + 6 ) -- inside
                model:PushFace( i + 5, i + 7, i + 3, i + 1 ) -- top
            end

            if numseg ~= maxseg then
                local i = numseg * 4 + 1
                model:PushFace( i + 2, i + 3, i + 1, i + 0 )
                model:PushFace( 1, 2, 4, 3 )
            end
        end
    end

    if physics then
        local convexes = {}
        model.convexes = convexes

        if iscone then
            for i = 1, c0 - 2, 2 do
                convexes[#convexes + 1] = { verts[c2], verts[i], verts[i + 1], verts[i + 2], verts[i + 3] }
            end
        else
            for i = 1, c0 - 4, 4 do
                convexes[#convexes + 1] = { verts[i], verts[i + 1], verts[i + 2], verts[i + 3], verts[i + 4], verts[i + 5], verts[i + 6], verts[i + 7] }
            end
        end
    end

    transform( verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- WEDGE
registerType( "wedge", function( param, data, threaded, physics )
    local verts, faces, convexes

    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5

    local tx = map( param.PrimTX or 0, -1, 1, -2, 2 )
    local ty = 1 - ( param.PrimTY or 0 )

    local model = simpleton.New()
    local verts = model.verts

    if ty == 0 then
        model:PushXYZ( dx, -dy, -dz )
        model:PushXYZ( dx, dy, -dz )
        model:PushXYZ( -dx, -dy, -dz )
        model:PushXYZ( -dx, dy, -dz )
        model:PushXYZ( -dx * tx, 0, dz )

    else
        model:PushXYZ( dx, -dy, -dz )
        model:PushXYZ( dx, dy, -dz )
        model:PushXYZ( -dx, -dy, -dz )
        model:PushXYZ( -dx, dy, -dz )
        model:PushXYZ( -dx * tx, dy * ty, dz )
        model:PushXYZ( -dx * tx, -dy * ty, dz )

    end

    if CLIENT then
        if ty == 0 then
            model:PushTriangle( 1, 2, 5 )
            model:PushTriangle( 2, 4, 5 )
            model:PushTriangle( 4, 3, 5 )
            model:PushTriangle( 3, 1, 5 )
            model:PushFace( 3, 4, 2, 1 )

    else
            model:PushFace( 1, 2, 5, 6 )
            model:PushTriangle( 2, 4, 5 )
            model:PushFace( 4, 3, 6, 5 )
            model:PushTriangle( 3, 1, 6 )
            model:PushFace( 3, 4, 2, 1 )

        end
    end

    if physics then
        model.convexes = { verts }
    end

    transform( verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )


-- WEDGE_CORNER
registerType( "wedge_corner", function( param, data, threaded, physics )
    local verts, faces, convexes

    local dx = ( isvector( param.PrimSIZE ) and param.PrimSIZE[1] or 1 ) * 0.5
    local dy = ( isvector( param.PrimSIZE ) and param.PrimSIZE[2] or 1 ) * 0.5
    local dz = ( isvector( param.PrimSIZE ) and param.PrimSIZE[3] or 1 ) * 0.5

    local tx = map( param.PrimTX or 0, -1, 1, -2, 2 )
    local ty = map( param.PrimTY or 0, -1, 1, 0, 2 )

    local model = simpleton.New()
    local verts = model.verts

    model:PushXYZ( dx, dy, -dz )
    model:PushXYZ( -dx, -dy, -dz )
    model:PushXYZ( -dx, dy, -dz )
    model:PushXYZ( -dx * tx, dy * ty, dz )

    if CLIENT then
        model:PushTriangle( 1, 3, 4 )
        model:PushTriangle( 2, 1, 4 )
        model:PushTriangle( 3, 2, 4 )
        model:PushTriangle( 1, 2, 3 )
    end

    if physics then
        model.convexes = { verts }
    end

    transform( verts, param.PrimMESHROT, param.PrimMESHPOS, threaded )

    return model
end )











--[=====[

--[[

    PREFAB SHAPES THAT CAN BE INSERTED INTO A VERTEX/CONVEX TABLE

]]

local simpleton
do

    -- copies and transforms vertex table, offsets face table by ibuffer
    local function copy( self, pos, rot, scale, ibuffer )
        local verts = {}
        local faces = table.Copy( self.faces )

        if ibuffer then
            for faceid = 1, #faces do
                local face = faces[faceid]
                for vertid = 1, #face do
                    face[vertid] = face[vertid] + ibuffer
                end
            end
        end

        for i = 1, #self.verts do
            local vertex = Vector( self.verts[i] )

            if scale then
                mulVec( vertex, scale )
            end
            if rot then
                rotateVec( vertex, rot )
            end
            if pos then
                addVec( vertex, pos )
            end

            verts[i] = vertex
        end

        return verts, faces
    end

    -- inserts a simpleton into verts, faces, convexes
    local function insert( self, verts, faces, convexes, pos, rot, scale, hull )
        local pverts, pfaces = self:copy( pos, rot, scale, ( verts and faces ) and #verts or 0 )

        if faces then
            for faceid = 1, #pfaces do
                faces[#faces + 1] = pfaces[faceid]
            end
        end

        if convexes and not hull then
            hull = {}
            convexes[#convexes + 1] = hull
        end

        if hull or verts then
            for i = 1, #pverts do
                local vertex = pverts[i]
                if hull then
                    hull[#hull + 1] = vertex
                end
                if verts then
                    verts[#verts + 1] = vertex
                end
            end
        end

        return pverts, pfaces
    end

    local types = {}

    function simpleton( name )
        return types[name]
    end

    local function register( name, pverts, pfaces )
        types[name] = { name = name, verts = pverts, faces = pfaces, copy = copy, insert = insert }
        return types[name] or types.cube
    end

    Addon.construct.simpleton = {
        get = simpleton,
        set = function ( name, pverts, pfaces )
            return { name = name, verts = pverts, faces = pfaces, copy = copy, insert = insert }
        end,
        register = register,
    }

    register( "plane",
    {
        Vector( -0.5, 0.5, 0 ),
        Vector( -0.5, -0.5, 0 ),
        Vector( 0.5, -0.5, 0 ),
        Vector( 0.5, 0.5, 0 ),
    },
    {
        { 1, 2, 3, 4 },

    } )

    register( "cube",
    {
        Vector( -0.5, 0.5, -0.5 ),
        Vector( -0.5, 0.5, 0.5 ),
        Vector( 0.5, 0.5, -0.5 ),
        Vector( 0.5, 0.5, 0.5 ),
        Vector( -0.5, -0.5, -0.5 ),
        Vector( -0.5, -0.5, 0.5 ),
        Vector( 0.5, -0.5, -0.5 ),
        Vector( 0.5, -0.5, 0.5 )
    },
    {
        { 1, 5, 6, 2 },
        { 5, 7, 8, 6 },
        { 7, 3, 4, 8 },
        { 3, 1, 2, 4 },
        { 4, 2, 6, 8 },
        { 1, 3, 7, 5 }
    } )

    types.slider_cube = types.cube

    register( "slider_wedge",
    {
        Vector( -0.5, -0.5, 0.5 ),
        Vector( -0.5, 0.5, 0.3 ),
        Vector( -0.5, -0.5, 0.3 ),
        Vector( 0.5, -0, -0.5 ),
        Vector( 0.5, -0.5, 0.3 ),
        Vector( 0.5, -0.5, 0.5 ),
        Vector( 0.5, 0.5, 0.5 ),
        Vector( 0.5, 0.5, 0.3 ),
        Vector( -0.5, 0.5, 0.5 ),
        Vector( -0.5, 0, -0.5 ),
    },
    {
        { 9, 1, 6, 7 },
        { 9, 2, 3, 1 },
        { 1, 3, 5, 6 },
        { 6, 5, 8, 7 },
        { 7, 8, 2, 9 },
        { 3, 10, 4, 5 },
        { 8, 4, 10, 2 },
        { 2, 10, 3 },
        { 5, 4, 8 },
    } )

    register( "slider_spike",
    {
        Vector( 0.5, -0.5, 0.3 ),
        Vector( -0.5, -0.5, 0.5 ),
        Vector( -0.5, -0.5, 0.3 ),
        Vector( 0.5, 0.5, 0.3 ),
        Vector( 0, 0, -0.5 ),
        Vector( -0.5, 0.5, 0.3 ),
        Vector( 0.5, 0.5, 0.5 ),
        Vector( 0.5, -0.5, 0.5 ),
        Vector( -0.5, 0.5, 0.5 ),
    },
    {
        { 3, 5, 1 },
        { 6, 5, 3 },
        { 1, 5, 4 },
        { 4, 5, 6 },
        { 9, 6, 3, 2 },
        { 2, 3, 1, 8 },
        { 8, 1, 4, 7 },
        { 7, 4, 6, 9 },
        { 7, 9, 2, 8 },
    } )

    register( "slider_blade",
    {
        Vector( 0.5, 0.5, 0.5 ),
        Vector( 0.5, -0.5, 0.5 ),
        Vector( 0.5, -0.25, 0.153185 ),
        Vector( 0.433013, -0.5, 0.173407 ),
        Vector( 0.433013, 0.5, 0.173407 ),
        Vector( 0.433013, -0.25, -0.173407 ),
        Vector( 0.25, -0.25, -0.412490 ),
        Vector( 0.25, -0.5, -0.065675 ),
        Vector( 0.25, 0.5, -0.065675 ),
        Vector( 0, -0.25, -0.5 ),
        Vector( 0, -0.5, -0.153185 ),
        Vector( -0, 0.5, -0.153185 ),
        Vector( -0.25, -0.25, -0.412490 ),
        Vector( -0.25, -0.5, -0.065675 ),
        Vector( -0.25, 0.5, -0.065675 ),
        Vector( -0.433013, -0.25, -0.173407 ),
        Vector( -0.433013, -0.5, 0.173407 ),
        Vector( -0.433013, 0.5, 0.173407 ),
        Vector( -0.5, -0.5, 0.5 ),
        Vector( -0.5, 0.5, 0.5 ),
        Vector( -0.5, -0.25, 0.153186 ),
    },
    {
        { 1, 2, 3 },
        { 2, 4, 6, 3 },
        { 3, 6, 5, 1 },
        { 4, 8, 7, 6 },
        { 6, 7, 9, 5 },
        { 11, 10, 7, 8 },
        { 9, 7, 10, 12 },
        { 14, 13, 10, 11 },
        { 12, 10, 13, 15 },
        { 17, 16, 13, 14 },
        { 15, 13, 16, 18 },
        { 21, 16, 17, 19 },
        { 20, 18, 16, 21 },
        { 20, 21, 19 },
        { 19, 17, 14, 11, 8, 4, 2 },
        { 1, 5, 9, 12, 15, 18, 20 },
        { 2, 1, 20, 19 },
     } )

end




--[[

    COMPLEX SHAPES

]]

registerType( "rail_slider", function( param, data, thread, physics )
    local verts, faces, convexes = {}

    if CLIENT then faces = {} end
    if physics then convexes = {} end


    -- base
    local bpos = isvector( param.PrimBPOS ) and Vector( param.PrimBPOS ) or Vector( 1, 1, 1 )
    local bdim = isvector( param.PrimBDIM ) and Vector( param.PrimBDIM ) or Vector( 1, 1, 1 )

    bpos.z = bpos.z + bdim.z * 0.5


    -- contact point
    local cpos = isvector( param.PrimCPOS ) and Vector( param.PrimCPOS ) or Vector( 1, 1, 1 )
    local crot = isangle( param.PrimCROT ) and Angle( param.PrimCROT ) or Angle()
    local cdim = isvector( param.PrimCDIM ) and Vector( param.PrimCDIM ) or Vector( 1, 1, 1 )

    cpos.y = cpos.y + cdim.y * 0.5
    cpos.z = cpos.z + cdim.z * 0.5


    -- base
    if tobool( param.PrimBASE ) then
        local cube = simpleton( "cube" )
        cube:insert( verts, faces, convexes, bpos, nil, bdim )
    end


    -- contact point
    local ctype = simpleton( tostring( param.PrimCTYPE ) )
    local cbits = math_floor( tonumber( param.PrimCENUMS ) or 0 )

    local cgap = tonumber( param.PrimCGAP ) or 0
    cgap = cgap + cdim.y

    local flip = {
        Vector( 1, 1, 1 ), -- front left
        Vector( 1, -1, 1 ), -- front right
        Vector( -1, 1, 1 ), -- rear left
        Vector( -1, -1, 1 ), -- rear right
    }

    local ENUM_CDOUBLE = 16
    local double = bit.band( cbits, ENUM_CDOUBLE ) == ENUM_CDOUBLE


    -- flange
    local fbits, getflange = math_floor( tonumber( param.PrimFENUMS ) or 0 )

    local ENUM_FENABLE = 1
    if bit.band( fbits, ENUM_FENABLE ) == ENUM_FENABLE then
        local fdim
        if double then
            fdim = Vector( cdim.x, cgap - cdim.y, cdim.z * 0.25 )
        else
            fdim = Vector( cdim.x, tonumber( param.PrimFGAP ) or 1, cdim.z * 0.25 )
        end

        if fdim.y > 0 then
            local ftype = simpleton( tostring( param.PrimFTYPE ) )

            function getflange( i, pos, rot, side )
                local s = bit.lshift( 1, i - 1 )

                if bit.band( fbits, s ) == s then
                    local pos = Vector( pos )

                    pos = pos - ( rot:Right() * ( fdim.y * 0.5 + cdim.y * 0.5 ) * side.y )
                    pos = pos + ( rot:Up() * ( cdim.z * 0.5 - fdim.z * 0.5 ) )

                    ftype:insert( verts, faces, convexes, pos, rot, fdim )
                end
            end
        end
    end


    -- builder
    for i = 1, 4 do
        local side = bit.lshift( 1, i - 1 )

        if bit.band( cbits, side ) == side then
            side = flip[i]

            local pos = cpos * side
            local rot = Angle( -crot.p * side.x, crot.y * side.x * side.y, crot.r * side.y )

            pos.x = pos.x + ( cdim.x * side.x * 0.5 )

            ctype:insert( verts, faces, convexes, pos, rot, cdim )

            if getflange then getflange( i, pos, rot, side ) end

            if double then
                pos = pos - ( rot:Right() * side.y * cgap )
                ctype:insert( verts, faces, convexes, pos, rot, cdim )
            end
        end
    end

    transform( verts, param.PrimMESHROT, param.PrimMESHPOS, thread )

    return { verts = verts, faces = faces, convexes = convexes }
end )



--[[

    BASIC SHAPES

]]









--]=====]
