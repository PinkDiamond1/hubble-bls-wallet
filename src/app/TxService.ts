import { ethers } from "../../deps/index.ts";

import AddTransactionFailure from "./AddTransactionFailure.ts";
import * as env from "./env.ts";
import TxTable, { TransactionData } from "./TxTable.ts";
import WalletService from "./WalletService.ts";

export default class TxService {
  constructor(
    public txTable: TxTable,
    public pendingTxTable: TxTable,
    public walletService: WalletService,
  ) {}

  async add(txData: TransactionData): Promise<AddTransactionFailure[]> {
    const { failures, nextNonce } = await this.walletService.checkTx(txData);

    if (failures.length > 0) {
      return failures;
    }

    const lowestAcceptableNonce = await this.LowestAcceptableNonce(
      nextNonce,
      txData.pubKey,
    );

    if (lowestAcceptableNonce.gt(txData.nonce)) {
      console.warn(
        "Not implemented: replace pending transaction",
      );

      return [
        {
          type: "duplicate-nonce",
          description: [
            `nonce ${txData.nonce} is already queued for aggregation (the`,
            `lowest acceptable nonce for this wallet is`,
            `${lowestAcceptableNonce.toString()})`,
          ].join(" "),
        },
      ];
    }

    if (lowestAcceptableNonce.eq(txData.nonce)) {
      await this.txTable.add(txData);
      await this.tryMovePendingTxs(txData.pubKey, lowestAcceptableNonce.add(1));
    } else {
      await this.ensurePendingTxSpace();
      await this.pendingTxTable.add(txData);
    }

    return [];
  }

  async LowestAcceptableNonce(
    nextChainNonce: ethers.BigNumber,
    pubKey: string,
  ): Promise<ethers.BigNumber> {
    const nextLocalNonce = await this.txTable.nextNonceOf(pubKey);

    const lowestAcceptableNonce = nextChainNonce.gt(nextLocalNonce ?? 0)
      ? nextChainNonce
      : ethers.BigNumber.from(nextLocalNonce);

    return lowestAcceptableNonce;
  }

  async tryMovePendingTxs(
    pubKey: string,
    lowestAcceptableNonce: ethers.BigNumber,
  ) {
    while (true) {
      const pendingTxsToRemove: TransactionData[] = [];
      const txsToAdd: TransactionData[] = [];

      const pendingTxs = await this.pendingTxTable.selectByPubKey(pubKey, 100);

      if (pendingTxs.length === 0) {
        break;
      }

      let foundGap = false;

      for (const tx of pendingTxs) {
        if (lowestAcceptableNonce.gt(tx.txId!)) {
          console.warn("Nonce from past was in pending tx table");
          pendingTxsToRemove.push(tx);
          continue;
        }

        if (lowestAcceptableNonce.eq(tx.txId!)) {
          pendingTxsToRemove.push(tx);
          const txWithoutId = { ...tx };
          delete txWithoutId.txId;
          txsToAdd.push(txWithoutId);
          continue;
        }

        foundGap = true;
        break;
      }

      await this.txTable.add(...txsToAdd);
      await this.pendingTxTable.remove(...pendingTxsToRemove);

      if (foundGap) {
        break;
      }
    }
  }

  async ensurePendingTxSpace() {
    const size = await this.pendingTxTable.count();

    if (size >= env.MAX_PENDING_TXS) {
      const first = await this.pendingTxTable.First();

      if (first === null) {
        console.warn(
          "Pending txs unexpectedly empty when it seemed to need pruning",
        );

        return;
      }

      const newFirstId = first.txId! + (Number(size) - env.MAX_PENDING_TXS + 1);

      this.pendingTxTable.clearBeforeId(newFirstId);
    }
  }
}
