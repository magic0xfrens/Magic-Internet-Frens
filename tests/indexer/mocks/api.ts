type Row = Record<string, any>;

export const apiRows = new Map<string, Row[]>();

const valueAt = (row: Row, column: unknown) => row[String(column).split(".").at(-1)!];
const matches = (row: Row, condition: any): boolean => {
  if (!condition) return true;
  if (condition.op === "and") return condition.args.every((x: any) => matches(row, x));
  if (condition.op === "eq") return valueAt(row, condition.column) === condition.value;
  if (condition.op === "gte") return valueAt(row, condition.column) >= condition.value;
  if (condition.op === "ne") return valueAt(row, condition.column) !== condition.value;
  return true;
};

const query = () => {
  let rows: Row[] = [];
  let condition: any;
  let ordering: any;
  let max: number | undefined;
  const q: any = {
    from(table: { name: string }) { rows = [...(apiRows.get(table.name) ?? [])]; return q; },
    where(next: any) { condition = next; return q; },
    orderBy(next: any) { ordering = next; return q; },
    limit(next: number) { max = next; return q; },
    then(resolve: (rows: Row[]) => unknown, reject: (error: unknown) => unknown) {
      try {
        let out = rows.filter((row) => matches(row, condition));
        if (ordering?.direction === "desc") {
          out.sort((a, b) => valueAt(a, ordering.column) < valueAt(b, ordering.column) ? 1 : -1);
        }
        if (max != null) out = out.slice(0, max);
        return resolve(out);
      } catch (error) { return reject(error); }
    },
  };
  return q;
};

export const db = { select: () => query() };
