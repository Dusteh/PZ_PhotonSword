"""Read and write Project Zomboid's text DirectX (.x) animation files.

A vanilla animation file (media/anims_X/Bob/*.x) holds the skeleton (a Frame hierarchy), the
skinned Body mesh, and one AnimationSet of per-bone scale (S), rotation (R) and translation (T)
keys. Matrices are row-major for row vectors (v * M, translation in the last row); a bone's world
matrix is its local matrix times its parent's. Rotation keys are quaternions written w, x, y, z.
"""

import re

import numpy as np

TOKEN = re.compile(r'"[^"]*"|[A-Za-z_][A-Za-z0-9_\-]*|-?\d+\.?\d*(?:[eE][-+]?\d+)?|[{};,]')


class Bone:
    def __init__(self, name, parent):
        self.name, self.parent, self.children = name, parent, []
        self.matrix = np.eye(4)


class XFile:
    def __init__(self, path):
        self.path = path
        self.text = open(path, encoding="latin-1").read()
        self.bones = {}      # name -> Bone, in file order
        self.roots = []
        self.vertices = None  # (n, 3)
        self.faces = []       # vertex index lists
        self.skins = []       # (bone name, indices, weights, offset matrix)
        self.ticks = 4800
        self.keys = {}        # bone -> {"S"|"R"|"T": [(tick, values)]}
        self._parse()

    # -- parsing -----------------------------------------------------------------------------
    def _parse(self):
        body = self.text[self.text.index("\n", self.text.index("xof")):]
        # Skip template declarations.
        body = re.sub(r"template\s+\w+\s*\{[^{}]*\}", "", body)
        self.tokens = TOKEN.findall(body)
        self.pos = 0
        while self.pos < len(self.tokens):
            self._statement(None)

    def _next(self):
        token = self.tokens[self.pos]
        self.pos += 1
        return token

    def _numbers(self, count):
        out = []
        while len(out) < count:
            token = self._next()
            if token not in ";,":
                out.append(float(token))
        return out

    def _skip_block(self):
        depth = 1
        while depth:
            token = self._next()
            depth += token == "{"
            depth -= token == "}"

    def _close(self):
        while self._next() != "}":
            pass

    def _statement(self, bone):
        kind = self._next()
        if kind == "}":
            return "}"
        if kind in ";,":
            return None
        name = None
        if self.tokens[self.pos] != "{":
            name = self._next()
        assert self._next() == "{", (kind, name)
        if kind == "Frame":
            child = Bone(name, bone)
            self.bones[name] = child
            (bone.children if bone else self.roots).append(child)
            while self._statement(child) != "}":
                pass
        elif kind == "FrameTransformMatrix":
            bone.matrix = np.array(self._numbers(16)).reshape(4, 4)
            self._close()
        elif kind == "Mesh":
            self._mesh()
        elif kind == "AnimTicksPerSecond":
            self.ticks = int(self._numbers(1)[0])
            self._close()
        elif kind == "AnimationSet":
            self.animation_name = name
            while self._statement(None) != "}":
                pass
        elif kind == "Animation":
            self._animation()
        else:
            self._skip_block()
        return None

    def _mesh(self):
        count = int(self._numbers(1)[0])
        self.vertices = np.array(self._numbers(count * 3)).reshape(count, 3)
        faces = int(self._numbers(1)[0])
        for _ in range(faces):
            n = int(self._numbers(1)[0])
            self.faces.append([int(v) for v in self._numbers(n)])
        while True:
            token = self._next()
            if token == "}":
                return
            if token == "SkinWeights":
                assert self._next() == "{"
                bone = self._next().strip('"')
                n = int(self._numbers(1)[0])
                indices = [int(v) for v in self._numbers(n)]
                weights = self._numbers(n)
                offset = np.array(self._numbers(16)).reshape(4, 4)
                self.skins.append((bone, np.array(indices, dtype=int), np.array(weights), offset))
                self._close()
            elif token[0].isalpha():  # any other block: normals, UVs, materials, DeclData, ...
                if self.tokens[self.pos] != "{":
                    self._next()
                assert self._next() == "{"
                self._skip_block()

    def _animation(self):
        bone, keys = None, {}
        while True:
            token = self._next()
            if token == "}":
                break
            if token == "{":
                bone = self._next()
                assert self._next() == "}"
            elif token == "AnimationKey":
                kind = self._next() if self.tokens[self.pos] != "{" else None
                assert self._next() == "{"
                key_type = int(self._numbers(1)[0])
                n = int(self._numbers(1)[0])
                frames = []
                for _ in range(n):
                    tick = int(self._numbers(1)[0])
                    size = int(self._numbers(1)[0])
                    frames.append((tick, self._numbers(size)))
                keys["SRT"[[1, 0, 2].index(key_type)] if key_type in (0, 1, 2) else kind] = frames
                self._close()
        self.keys[bone] = keys

    # -- pose math ---------------------------------------------------------------------------
    def sample(self, bone, kind, tick):
        frames = self.keys.get(bone, {}).get(kind)
        if not frames:
            return None
        if tick <= frames[0][0]:
            return np.array(frames[0][1])
        for (t0, a), (t1, b) in zip(frames, frames[1:]):
            if t0 <= tick <= t1:
                f = (tick - t0) / max(1, t1 - t0)
                a, b = np.array(a), np.array(b)
                if kind == "R":
                    if np.dot(a, b) < 0:
                        b = -b
                    q = a + (b - a) * f
                    return q / np.linalg.norm(q)
                return a + (b - a) * f
        return np.array(frames[-1][1])

    def local_matrices(self, tick):
        """Each bone's local matrix at tick; bones without keys keep their frame matrix."""
        out = {}
        for name, bone in self.bones.items():
            r = self.sample(name, "R", tick)
            if r is None:
                out[name] = bone.matrix
                continue
            s = self.sample(name, "S", tick)
            t = self.sample(name, "T", tick)
            out[name] = srt_matrix(s if s is not None else np.ones(3), r, t if t is not None else bone.matrix[3, :3])
        return out

    def world_matrices(self, local):
        out = {}

        def walk(bone, parent):
            out[bone.name] = local[bone.name] @ parent
            for child in bone.children:
                walk(child, out[bone.name])

        for root in self.roots:
            walk(root, np.eye(4))
        return out

    def skinned(self, world):
        """Body vertex positions under world bone matrices (linear blend skinning)."""
        verts = np.hstack([self.vertices, np.ones((len(self.vertices), 1))])
        out = np.zeros_like(verts)
        total = np.zeros(len(verts))
        for bone, indices, weights, offset in self.skins:
            m = offset @ world[bone]
            out[indices] += (verts[indices] @ m) * weights[:, None]
            total[indices] += weights
        total[total == 0] = 1
        return out[:, :3] / total[:, None]


def quat_matrix(q):
    """Rotation matrix (row-vector form) for a .x rotation key (w, x, y, z)."""
    w, x, y, z = q
    # .x keys store the rotation's conjugate relative to the usual column-vector form, so the
    # usual column-vector matrix is the row-vector matrix here.
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)],
        [2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)],
        [2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)],
    ])


def matrix_quat(m):
    """Inverse of quat_matrix."""
    m = np.asarray(m)[:3, :3]
    trace = m[0, 0] + m[1, 1] + m[2, 2]
    if trace > 0:
        s = np.sqrt(trace + 1) * 2
        q = [s / 4, (m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s]
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        q = [(m[2, 1] - m[1, 2]) / s, s / 4, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s]
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        q = [(m[0, 2] - m[2, 0]) / s, (m[0, 1] + m[1, 0]) / s, s / 4, (m[1, 2] + m[2, 1]) / s]
    else:
        s = np.sqrt(1 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        q = [(m[1, 0] - m[0, 1]) / s, (m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, s / 4]
    q = np.array(q)
    return q / np.linalg.norm(q)


def srt_matrix(s, r, t):
    m = np.eye(4)
    m[:3, :3] = np.diag(s) @ quat_matrix(r)
    m[3, :3] = t
    return m
