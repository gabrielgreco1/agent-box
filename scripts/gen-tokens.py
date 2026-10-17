#!/usr/bin/env python3
"""gen-tokens.py - ESQUELETO (Fatia 0). Conteúdo completo em: T1-03.

Contrato
  Entrada : design/tokens/*.json e design/motion/tokens.json (novos; nunca legacy/design).
  Saída   : AgentBoxDesignSystem/Tokens/*.generated.swift (DS.Color, DS.Font, DS.Space,
            DS.Radius, Motion), MotionTokens.generated.swift e tokens.js.
            Determinístico; --check falha (exit 1) se os arquivos gerados estão defasados.
  Exit    : 0 sucesso; != 0 falha; 64 = "não implementado" (esqueleto).
Uso: scripts/gen-tokens.py [--check] [--help]
"""
import sys


def main(argv):
    if any(a in ("-h", "--help") for a in argv[1:]):
        print(__doc__)
        return 0
    print("ERRO: gen-tokens.py ainda não implementado (completa em T1-03).", file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv))
